extends SceneTree
## Run with --script res://tools/session_test.gd -- --session-test.
## Optional --session-capture=/absolute/path.png requires a real renderer.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error("SESSION FAIL: " + description)
	else:
		print("SESSION OK: " + description)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	current_scene = main
	for i in 12:
		await physics_frame
	var session: Node = main.systems.get("session")
	check(session != null, "session is loaded")
	if session == null:
		quit(1)
		return
	session.started = false
	session.show_menu()
	check(paused and session.opened and session.menu.visible, "opening screen pauses the world")
	var position: Vector3 = main.vehicle.global_position
	var playtime: float = main.systems.save_load.playtime
	for i in 20:
		await process_frame
	check(main.vehicle.global_position == position, "vehicle stays frozen in menu")
	check(main.systems.save_load.playtime == playtime, "playtime stays frozen in menu")
	check(session.resume_button.has_focus(), "opening screen supports keyboard navigation")
	session.select_activity(0)
	check(session.waypoint == Vector2(709, 528), "first job points at the real dispatch trigger")
	check(session.route.size() >= 4, "dispatch gets a street route")
	var router := preload("res://scripts/ui/street_route.gd").new()
	var route := router.build_route(Vector2(193, 517), Vector2(709, 528))
	for i in range(1, route.size()):
		var span: Vector2 = route[i] - route[i - 1]
		check(absf(span.x) < 0.01 or absf(span.y) < 0.01, "route segment %d follows a street axis" % i)
	check(router.build_route(Vector2(193, 517), Vector2(-620, 150)).is_empty(), "unmapped roads use bearing instead of fake GPS")
	var point := Vector2(193, 563)
	check(session.map.map_to_world(session.map.world_to_map(point)).distance_to(point) < 0.01, "map coordinate conversion round-trips")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = session.map.world_to_map(Vector2(709, 558))
	session.map._map_input(click)
	check(session.waypoint_name == "Impound", "nearby map markers select the closest activity")
	session.select_activity(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--session-capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--session-capture="))
	session.resume()
	check(not paused and not session.menu.visible and session.started, "resume restores play")
	var combat: Node = main.systems.combat
	combat._wheel_open_now()
	check(combat._wheel_open, "weapon wheel opens before pause")
	session.show_menu()
	check(not combat._wheel_open and Engine.time_scale == 1.0, "pause closes weapon wheel and releases slow motion")
	check(Engine.max_fps == 30, "menu caps rendering work")
	session.resume()
	var mission: Node = main.systems.mission_hook_and_ladder
	mission._start_mission()
	check(session.navigation_target().pos == Vector2(587.5, -360), "active mission target overrides selected waypoint")
	mission.state = 3
	check(session.navigation_target().pos == Vector2(709, 558), "delivery guidance switches to impound")
	mission._abort_mission()
	check(session.navigation_target().pos == session.waypoint, "waypoint returns after mission ends")
	session.clear_destination()
	check(session.navigation_target().is_empty(), "clear removes navigation marker")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	session._input(event)
	check(paused and session.opened, "Escape opens pause menu")
	session._input(event)
	check(not paused and not session.opened, "Escape resumes paused game")
	check(main.systems.hud_gta._ui.visible, "resume restores HUD")
	main.systems.on_foot._exit_vehicle()
	check(main.on_foot and is_instance_valid(main.character), "vehicle exit still works")
	session.show_menu()
	check(paused, "pause works on foot")
	session.resume()
	main.systems.on_foot._board_vehicle(main.vehicle)
	check(not main.on_foot, "vehicle entry still works after pause")
	print("SESSION TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
