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
	# D-065: the game has ambient occlusion; without it a white sleeve against a
	# white shirt has no crease at all, and an armpit reads as a slit.
	env.environment.ssao_enabled = true
	env.environment.ssao_radius = 0.35
	env.environment.ssao_intensity = 2.5
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
		["front", Vector3(0, 1.0, -3.1), Vector3(0, 0.94, 0)],
		["body_side", Vector3(-3.1, 1.0, 0), Vector3(0, 0.94, 0)],
		["torso", Vector3(-0.65, 1.30, -1.15), Vector3(0, 1.28, 0)],
		["hand", Vector3(-0.62, 0.84, -0.62), Vector3(-0.25, 0.82, 0)],
		["collar", Vector3(0.18, 1.60, -0.52), Vector3(0, 1.49, 0)],
		["collar_normals", Vector3(0.18, 1.60, -0.52), Vector3(0, 1.49, 0)],
		["gait", Vector3(-1.2, 1.1, -3.4), Vector3(0, 0.94, 0)],
		["normals", Vector3(0, 1.68, -0.65), Vector3(0, 1.66, 0)],
	]
	for shot in shots:
		if shot[0] == "gait":
			for i in 24:
				SKIN.animate(rig, 3.0, 1.0 / 60.0, true, true)
		else:
			# D-059: the standing views show the IDLE the player sees, not the bind
			# pose — 90 fixed steps of it, so the plate is the same every run.
			for i in 90:
				SKIN.animate(rig, 0.0, 1.0 / 60.0, false, true)
		if shot[0] == "normals" or shot[0] == "collar_normals":
			root.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
		else:
			root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		camera.position = shot[1]
		camera.look_at(shot[2])
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + shot[0] + ".png")
		print("CHARACTER REVIEW: " + shot[0])
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	# D-065: GAIT STRIPS. One frame of a walk says nothing about a walk. Eight
	# frames across one full stride (phase marks at TAU/8), side-on and from the
	# front quarter, at walking pace, a jog and full sprint — one image per gait
	# and view, the character cropped out of each frame. The pose is driven by
	# hand here, so the rig is frozen while each frame renders.
	for gait in [["walk", 1.4], ["jog", 3.2], ["sprint", 6.5]]:
		await _strip(rig, camera, float(gait[1]), str(gait[0]))
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


## Eight frames across one stride at `speed`, two views, cropped and tiled.
func _strip(rig: Dictionary, camera: Camera3D, speed: float, label: String) -> void:
	for i in 240:   # settle: at least two full cycles at any speed
		SKIN.animate(rig, speed, 1.0 / 60.0, true, true)
	var frames := 8
	var views := [["side", Vector3(-3.1, 1.0, 0.0)], ["quarter", Vector3(-2.3, 1.15, -2.3)]]
	for view in views:
		camera.position = view[1]
		camera.look_at(Vector3(0, 0.94, 0))
		var strip: Image = null
		var cw := 0
		var ch := 0
		for f in frames:
			var mark := float(f) * TAU / float(frames)
			var prev := float(rig["phase"])
			for guard in 2000:
				SKIN.animate(rig, speed, 1.0 / 60.0, true, true)
				var ph := float(rig["phase"])
				var a := fmod(prev - mark + TAU * 2.0, TAU)
				var b := fmod(ph - mark + TAU * 2.0, TAU)
				prev = ph
				if b < a:
					break
			for i in 2:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			if strip == null:
				cw = int(img.get_width() * 0.42)
				ch = img.get_height()
				strip = Image.create(cw * frames, ch, false, img.get_format())
			var x0 := (img.get_width() - cw) / 2
			strip.blit_rect(img, Rect2i(x0, 0, cw, ch), Vector2i(cw * f, 0))
		strip.save_png(output + "/" + label + "_" + str(view[0]) + ".png")
		print("CHARACTER REVIEW: %s_%s (8 frames, %.1f m/s)" % [label, view[0], speed])
