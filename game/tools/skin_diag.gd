extends Node3D
## Diagnostic: is a patch a ZONE bug or a SHADING bug? Renders the same vantage
## four ways — lit, unshaded (albedo only), zone rainbow, and sun-off.
const FACTORY := preload("res://scripts/world/character_factory.gd")
const SKIN := preload("res://scripts/world/skinned_character.gd")
const OUT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/shots/skin"
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _skinmi: MeshInstance3D
var _jobs: Array = []
var _f := 0
var _busy := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	SKIN._no_disk = true
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.0, 0.55, 0.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.7)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = e
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-64.0), deg_to_rad(28.0), 0.0)
	_sun.light_energy = 0.95
	_sun.shadow_enabled = true
	add_child(_sun)
	_cam = Camera3D.new(); _cam.fov = 40.0; add_child(_cam); _cam.make_current()
	var holder := Node3D.new(); add_child(holder)
	SKIN.build(holder, FACTORY.book_config(), 0.0)
	var stack: Array = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MeshInstance3D and n.name == "Skin":
			_skinmi = n
	_jobs = ["lit", "noshadow", "unshaded", "zones"]

func _process(_d: float) -> void:
	_f += 1
	if _f < 6 or _busy: return
	if _jobs.is_empty():
		print("DIAG DONE"); get_tree().quit(0); return
	_busy = true
	_run(str(_jobs.pop_front()))

func _run(mode: String) -> void:
	_cam.global_position = Vector3(-2.20, 1.10, 0.05)
	_cam.look_at(Vector3(0.0, 1.00, 0.0), Vector3.UP)
	var m: StandardMaterial3D = _skinmi.material_override
	_sun.visible = true
	_sun.shadow_enabled = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	match mode:
		"noshadow":
			_sun.shadow_enabled = false
		"unshaded":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"zones":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var img := Image.create_empty(16, 1, false, Image.FORMAT_RGBA8)
			for i in 16:
				img.set_pixel(i, 0, Color.from_hsv(float(i) / 16.0, 0.95, 1.0))
			m.albedo_texture = ImageTexture.create_from_image(img)
	await _save("diag_side_" + mode)
	_busy = false

func _save(tag: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + tag + ".png")
	print("SHOT " + tag)
