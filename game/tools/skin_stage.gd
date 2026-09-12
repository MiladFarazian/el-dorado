extends SceneTree
## THE JUDGEMENT VANTAGES, WITH SKINNED PEOPLE IN THEM. Runs WINDOWED:
##   cd game/ && godot --script res://tools/skin_stage.gd -- --skinned
##   ...                                                  -- --factory
##
## WHY THIS TOOL HAS TO EXIST, and it is the finding that voided the previous
## mission's headline blocker:
##
##   `zz_shot.gd:126` builds the showcase row with
##       var factory := load("res://scripts/world/character_factory.gd")
##   and there is no `--skinned` gate anywhere in that file. `_build_mat_test`
##   is the ONLY thing that puts a character at (324.2, 0.05, 511.0), which is
##   what `face`, `torso`, `side`, `back` and `portrait` are aimed at, and what
##   `showcase_people` frames. So those five vantages render FACTORY bodies in
##   BOTH modes, and always have. Two 59-shot sweeps confirm it: with `--skinned`
##   on the command line the subject is pixel-identical and only background
##   traffic moves (torso: mean |dRGB| 0.399, and the differing pixels are the
##   taxi and the pickup, not the man).
##
##   The previous mission therefore attributed a "puffy rounded mass over the
##   shoulders with a rolled lip across the upper chest" to a body that was
##   never in the frame. It is the FACTORY's M21 swept shoulder girdle
##   (character_factory.gd:571-586). Correctly, it refused to guess.
##
## zz_shot.gd is not mine to edit, so this stages the same four vantages in the
## real main scene, under production lighting, with the builder chosen by flag.
## Same camera (40 deg vertical, D-080), same settle, same look-at targets.

const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")

const OUT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/skin6"

## [name, camera pos, look-at, hour] — face/torso/side/back copied VERBATIM from
## zz_shot.gd so the plates are comparable to every previous cycle's, plus a
## crowd view down the row and two the bar names for wardrobe.
const SHOTS: Array = [
	["face", Vector3(323.55, 1.62, 510.05), Vector3(324.2, 1.60, 511.0), 13.0],
	["torso", Vector3(323.0, 1.30, 509.6), Vector3(324.2, 1.15, 511.0), 13.0],
	["side", Vector3(322.0, 1.15, 511.05), Vector3(324.2, 1.05, 511.0), 13.0],
	["back", Vector3(324.2, 1.20, 513.2), Vector3(324.2, 1.10, 511.0), 13.0],
	["showcase_people", Vector3(326.5, 1.62, 506.4), Vector3(327.5, 1.15, 511.0), 13.0],
	["portrait", Vector3(322.6, 1.62, 508.6), Vector3(324.2, 1.35, 511.0), 13.0],
	# The wardrobe rows the bar cannot see from the four above: the hem and the
	# belt live at the waist, the apron and the vest on the flank.
	["waist", Vector3(323.0, 1.05, 509.7), Vector3(324.2, 0.99, 511.0), 13.0],
	["ward_side", Vector3(322.3, 1.30, 511.9), Vector3(324.2, 1.25, 511.0), 13.0],
	["night", Vector3(323.0, 1.30, 509.6), Vector3(324.2, 1.15, 511.0), 21.8],
]

var _main: Node = null
var _cam: Camera3D = null
var _f := 0
var _idx := 0
var _busy := false
var _tag := "skin"


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("skin_stage: needs a rendering window; --headless deadlocks capture.")
		quit(1)
		return
	_tag = "fact" if OS.get_cmdline_user_args().has("--factory") else "skin"
	DirAccess.make_dir_recursive_absolute(OUT + "/stage_" + _tag)
	change_scene_to_file("res://scenes/main.tscn")
	process_frame.connect(_tick)


func _tick() -> void:
	if _busy:
		return
	_f += 1
	if _f < 60:
		return                       # city, traffic and dressing settle first
	if _main == null:
		_main = current_scene
		if _main == null:
			return
		_stage()
		return
	if _idx >= SHOTS.size():
		quit(0)
		return
	_busy = true
	_shoot(SHOTS[_idx])


## The same row `zz_shot._build_mat_test` builds, with the same seed and the
## same configs — only the BUILDER changes. Same seed matters: it is what makes
## a factory plate and a skinned plate the same eight people in the same
## clothes, so a difference between the two plates is the architecture and
## nothing else.
func _stage() -> void:
	for n in _main.get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	var sysd: Variant = _main.get("systems")
	if sysd is Dictionary:
		for sys: Node in (sysd as Dictionary).values():
			for c in sys.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	var b: Object = SKIN if _tag == "skin" else FACTORY
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260803
	for k in 7:
		var p := Node3D.new()
		_main.add_child(p)
		p.global_position = Vector3(325.6 + 1.3 * float(k), 0.05, 511.0)
		var cfg: Dictionary = FACTORY.cop_config(rng) if k == 6 \
			else FACTORY.random_config(rng)
		b.call("build", p, cfg, 0.0)
	var book := Node3D.new()
	_main.add_child(book)
	book.global_position = Vector3(324.2, 0.05, 511.0)
	b.call("build", book, FACTORY.book_config(), 0.0)
	# Four more, one per archetype the wardrobe is most likely to fail on,
	# standing behind the row so one plate carries apron / hi-vis / hood / duty.
	var extra := ["SERVICE", "WORKER", "STREET", "OFFICE"]
	for k in extra.size():
		var r2 := RandomNumberGenerator.new()
		r2.seed = hash("wardrobe|%d" % [4, 2, 5, 3][k])
		var cfg2 := FACTORY._person(r2, FACTORY.SKIN_TONES[k % 6],
			FACTORY.HAIRS[k % 5], 1.0, 1.02)
		cfg2["shirt"] = FACTORY.SHIRTS[k % FACTORY.SHIRTS.size()]
		cfg2["pants"] = FACTORY.PANTS[k % FACTORY.PANTS.size()]
		cfg2["hat_color"] = FACTORY.HAT_COLORS[0]
		FACTORY._dress(cfg2, r2, [4, 2, 5, 3][k])
		var p2 := Node3D.new()
		_main.add_child(p2)
		p2.global_position = Vector3(325.0 + 1.3 * float(k), 0.05, 513.4)
		b.call("build", p2, cfg2, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 40.0                                   # D-080: a normal lens
	_cam.far = 4000.0
	_main.add_child(_cam)
	_cam.make_current()
	print("skin_stage: staged 12 %s bodies" % _tag)


func _shoot(s: Array) -> void:
	var sysd: Variant = _main.get("systems")
	if sysd is Dictionary:
		var sky: Variant = (sysd as Dictionary).get("sky_weather")
		if sky is Node and is_instance_valid(sky):
			(sky as Node).set("time_of_day", float(s[3]))
	_cam.global_position = s[1]
	_cam.look_at(s[2], Vector3.UP)
	await _settle(str(s[0]))


func _settle(nm: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/stage_%s/%s.png" % [OUT, _tag, nm])
	print("STAGE saved: %s/%s" % [_tag, nm])
	_idx += 1
	_busy = false
