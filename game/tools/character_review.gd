extends SceneTree
const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")
var output := "/tmp/edg-characters-before"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	create_timer(120.0).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("323d48")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cad7e8")
	env.environment.ambient_light_energy = 0.55
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.1
	stage.add_child(light)
	var person := Node3D.new()
	stage.add_child(person)
	var rig := SKIN.build(person, FACTORY.book_config(), 0.0)
	var camera := Camera3D.new()
	camera.fov = 35
	stage.add_child(camera)
	camera.make_current()
	var shots := [
		["face", Vector3(0, 1.68, -0.65), Vector3(0, 1.66, 0)],
		["profile", Vector3(-0.7, 1.68, -0.04), Vector3(0, 1.66, 0)],
		["full", Vector3(-1.2, 1.1, -3.4), Vector3(0, 0.94, 0)],
		["back", Vector3(0.9, 1.2, 3.2), Vector3(0, 0.95, 0)],
		["gait", Vector3(-1.2, 1.1, -3.4), Vector3(0, 0.94, 0)],
		["normals", Vector3(0, 1.68, -0.65), Vector3(0, 1.66, 0)],
	]
	for shot in shots:
		if shot[0] == "gait":
			for i in 24:
				SKIN.animate(rig, 3.0, 1.0 / 60.0, true, true)
		if shot[0] == "normals":
			root.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
		camera.position = shot[1]
		camera.look_at(shot[2])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + shot[0] + ".png")
		print("CHARACTER REVIEW: " + shot[0])
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	person.hide()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3107
	for i in 5:
		var head := Node3D.new()
		stage.add_child(head)
		head.position.x = (i - 2) * 0.27
		var cfg := FACTORY.random_config(rng)
		cfg.skinned_body = true
		FACTORY._build_head(head, cfg)
	camera.position = Vector3(0, 0.15, -1.5)
	camera.look_at(Vector3(0, 0.15, 0))
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/cast.png")
	quit()
