extends Node
## HUD CAPTURE — permanent QA infrastructure (was aa_hudshot). Screenshots the LIVE HUD (zz_shot hides every CanvasLayer, so it
## cannot judge HUD work). `godot -- --hudshot[=DIR]` — windowed only. Frame 150:
## save in-vehicle plate; then exit the vehicle (E), frame 260: save on-foot
## plate; quit. Deleted after use. Inert without the flag; smoke-guarded.
var main_ref: Node = null
var _f := 0
var _out := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/hud7/plates"


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return
	var on := false
	for a in OS.get_cmdline_user_args():
		if a == "--hudshot": on = true
		elif a.begins_with("--hudshot="): on = true; _out = a.substr(10)
	if not on:
		set_process(false); return
	if DisplayServer.get_name() == "headless":
		push_error("HUDSHOT: needs a rendering window."); set_process(false); return
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_d: float) -> void:
	_f += 1
	if _f == 150:
		_save("hud_vehicle")
	elif _f == 160:
		Input.action_press("enter_exit")
	elif _f == 164:
		Input.action_release("enter_exit")
	elif _f == 200:
		Input.action_press("accelerate")  # walk a few steps so stamina/tiers show
	elif _f == 250:
		Input.action_release("accelerate")
	elif _f == 262:
		_save("hud_foot")
	elif _f == 275:
		Input.action_press("aim")
	elif _f == 290:
		_save("hud_foot_aim")
		Input.action_release("aim")
	elif _f == 300:
		get_tree().quit(0)


func _save(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + nm + ".png")
	print("HUDSHOT saved: " + nm)
