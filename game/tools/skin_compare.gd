extends Node3D
## SKINNED vs FACTORY — the measurement rig. Runs as its OWN main scene, so it
## touches nothing the game loads:
##
##   cd game/
##   godot res://tools/skin_compare.tscn            # lit + matte + id, both paths
##   godot res://tools/skin_compare.tscn -- --gait  # add the gait sweep
##   godot res://tools/skin_compare.tscn -- --pop   # all 8 archetypes, dressed
##
## `--pop` is the wardrobe cycle's addition. The body was measured on ONE
## config (Book) because the body is one config's worth of anatomy; a wardrobe
## is eight, and the seam metric has to be re-earned on each of them — a
## garment is a second surface, and a second surface is exactly the thing this
## architecture exists to be sceptical of.
##
## Vantages are the judgement vantages from `scripts/systems/zz_shot.gd`,
## converted to character-relative offsets (Book stands at 324.2 / 0.05 / 511.0
## there, feet on 0.05). Same 40 deg vertical lens, same 1600x900 viewport, so a
## frame from here is directly comparable to a frame from the shot harness.
##
## Three passes per vantage:
##   lit    — sun at the game's 13:00 elevation over neutral ground. For eyes.
##   matte  — flat background, no ground. Silhouette, exactly extractable.
##   id     — every MeshInstance3D flat-shaded in a unique colour. Adjacent
##            pixels of different colour are OWNER-CHANGE EDGES: the pixel
##            length of visible seam between parts. That is the defect Milad is
##            describing, counted rather than argued about. A single skinned
##            surface scores zero by construction; the factory cannot.

const FACTORY := preload("res://scripts/world/character_factory.gd")
const SKIN := preload("res://scripts/world/skinned_character.gd")
const OUT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/shots/skin"

# name, camera offset from the figure's feet origin, look-at offset
const VANTAGE: Array = [
	["face", Vector3(0.85, 1.57, -0.85), Vector3(0.0, 1.55, 0.0)],
	["torso", Vector3(-1.20, 1.25, -1.40), Vector3(0.0, 1.10, 0.0)],
	["side", Vector3(-2.20, 1.10, 0.05), Vector3(0.0, 1.00, 0.0)],
	["back", Vector3(0.0, 1.15, 2.20), Vector3(0.0, 1.05, 0.0)],
	["portrait", Vector3(-1.60, 1.57, -2.40), Vector3(0.0, 1.30, 0.0)],
	# joint close-ups: the two the brief calls out by name
	["shoulder", Vector3(-0.95, 1.62, -0.62), Vector3(-0.17, 1.44, 0.0)],
	["elbow", Vector3(-0.78, 1.30, -0.55), Vector3(-0.22, 1.16, 0.0)],
	["full", Vector3(-1.30, 1.05, -3.40), Vector3(0.0, 0.90, 0.0)],
]
## Gait phases to hold the rig at. `animate()` blends exponentially toward its
## target, so each pose is stepped 30 times at 1/60 s to settle before the shot.
const GAIT: Array = [0.0, 0.7854, 1.5708, 2.3562, 3.1416, 3.927, 4.712, 5.4978]

var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _ground: MeshInstance3D
var _subject: Node3D          # holder the character hangs under
var _rig: Dictionary = {}
var _jobs: Array = []
var _f := 0
var _busy := false
var _gait_mode := false
var _pop_mode := false
var _cfg: Dictionary = {}
const ARCH: Array = ["CASUAL", "WESTERN", "WORKER", "OFFICE", "SERVICE",
	"STREET", "SCRUBS", "GAMEDAY"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_gait_mode = OS.get_cmdline_user_args().has("--gait")
	_pop_mode = OS.get_cmdline_user_args().has("--pop")
	SKIN._no_disk = true       # always bake for real here, never read a cache

	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.34, 0.40)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.58, 0.68)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = e
	add_child(_env)

	_sun = DirectionalLight3D.new()
	# 13:00 in the shot harness puts the sun high; the factory's own comments
	# quote 64 deg, so that is the elevation used here.
	_sun.rotation = Vector3(deg_to_rad(-64.0), deg_to_rad(28.0), 0.0)
	_sun.light_energy = 0.95
	_sun.shadow_enabled = true
	# A soft blob at 18 mm self-shadows into acne with the default cascade over
	# a 100 m range. The subject is 2 m tall and 3 m away; 14 m of shadow
	# distance puts the whole cascade budget on the figure.
	_sun.directional_shadow_max_distance = 14.0
	_sun.shadow_normal_bias = 0.6
	_sun.shadow_bias = 0.02
	add_child(_sun)

	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 24)
	_ground = MeshInstance3D.new()
	_ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.30, 0.31)
	gm.roughness = 0.95
	_ground.material_override = gm
	add_child(_ground)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 200.0
	add_child(_cam)
	_cam.make_current()

	_subject = Node3D.new()
	add_child(_subject)

	if _pop_mode:
		for ac: Array in _arch_configs():
			for path in ["old", "new"]:
				for v in VANTAGE:
					if not (str(v[0]) in ["torso", "side", "back", "full"]):
						continue
					for pass_name in ["lit", "matte", "id"]:
						_jobs.append({"path": path, "vantage": v,
							"pass": pass_name, "phase": -1.0,
							"cfg": ac[1], "arch": ac[0]})
		return
	for path in ["old", "new"]:
		for v in VANTAGE:
			for pass_name in ["lit", "matte", "id"]:
				_jobs.append({"path": path, "vantage": v, "pass": pass_name,
					"phase": -1.0})
		if _gait_mode:
			for gi in GAIT.size():
				for vn in ["shoulder", "elbow", "full"]:
					for v in VANTAGE:
						if str(v[0]) == vn:
							_jobs.append({"path": path, "vantage": v,
								"pass": "id", "phase": float(GAIT[gi]),
								"gi": gi})
							_jobs.append({"path": path, "vantage": v,
								"pass": "lit", "phase": float(GAIT[gi]),
								"gi": gi})


func _process(_d: float) -> void:
	_f += 1
	if _f < 6 or _busy:
		return
	if _jobs.is_empty():
		print("SKINCOMPARE DONE")
		get_tree().quit(0)
		return
	_busy = true
	_run(_jobs.pop_front())


## The eight wardrobes, rolled through `character_factory._dress` itself so the
## archetype under the camera is the one the shipping path produces.
func _arch_configs() -> Array:
	var out: Array = []
	for o in ARCH.size():
		var r := RandomNumberGenerator.new()
		r.seed = hash("wardrobe|%d" % o)
		var cfg := FACTORY._person(r, FACTORY.SKIN_TONES[o % 6],
			FACTORY.HAIRS[o % 5], 1.0, 1.02)
		cfg["shirt"] = FACTORY.SHIRTS[o % FACTORY.SHIRTS.size()]
		cfg["pants"] = FACTORY.PANTS[o % FACTORY.PANTS.size()]
		cfg["hat_color"] = FACTORY.HAT_COLORS[0]
		FACTORY._dress(cfg, r, o)
		out.append([ARCH[o], cfg])
	var rc := RandomNumberGenerator.new()
	rc.seed = 7
	out.append(["COP", FACTORY.cop_config(rc)])
	return out


func _build(path: String) -> void:
	for c in _subject.get_children():
		_subject.remove_child(c)
		c.queue_free()
	var holder := Node3D.new()
	_subject.add_child(holder)
	var cfg: Dictionary = _cfg if not _cfg.is_empty() else FACTORY.book_config()
	if path == "old":
		_rig = FACTORY.build(holder, cfg, 0.0)
	else:
		_rig = SKIN.build(holder, cfg, 0.0)


## Flat-shade every MeshInstance3D under the subject in its own colour. i*13 mod
## 1000 is injective under 1000 parts, and the 25-step cube survives sRGB
## round-trip, so two parts can never quantise to the same id.
func _paint_ids() -> Array:
	var out: Array = []
	var stack: Array = [_subject]
	var i := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var v := (i * 13) % 1000
			var col := Color((float(v / 100) * 25.0 + 15.0) / 255.0,
				(float((v / 10) % 10) * 25.0 + 15.0) / 255.0,
				(float(v % 10) * 25.0 + 15.0) / 255.0)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = col
			out.append((n as MeshInstance3D).material_override)
			(n as MeshInstance3D).material_override = m
			i += 1
	return out


func _restore_ids(saved: Array) -> void:
	var stack: Array = [_subject]
	var i := 0
	var list: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			list.append(n)
	for k in list.size():
		if k < saved.size():
			(list[k] as MeshInstance3D).material_override = saved[k]


func _run(job: Dictionary) -> void:
	_cfg = job.get("cfg", {})
	_build(str(job["path"]))
	var phase := float(job["phase"])
	if phase >= 0.0:
		_rig["phase"] = phase
		# settle the exponential blends at a walking 1.6 m/s
		for i in 40:
			if str(job["path"]) == "old":
				FACTORY.animate(_rig, 1.6, 1.0 / 60.0, true, true)
			else:
				SKIN.animate(_rig, 1.6, 1.0 / 60.0, true, true)
			_rig["phase"] = phase   # hold the phase, only let the blends settle
	var v: Array = job["vantage"]
	_cam.global_position = v[1]
	_cam.look_at(v[2], Vector3.UP)
	var pass_name := str(job["pass"])
	var e := _env.environment
	var saved: Array = []
	if pass_name == "lit":
		e.background_color = Color(0.30, 0.34, 0.40)
		e.ambient_light_energy = 0.42
		_sun.visible = true
		_ground.visible = true
	else:
		# flat, unmistakable background; no ground, no light contribution
		e.background_color = Color(0.0, 1.0, 0.0)
		e.ambient_light_energy = 0.0 if pass_name == "id" else 0.42
		_sun.visible = pass_name != "id"
		_ground.visible = false
		if pass_name == "id":
			# MSAA blends across a part boundary and invents ids that were never
			# drawn, which inflates both the edge count and the part count. The
			# id pass is a measurement, so it runs aliased.
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			saved = _paint_ids()
	if pass_name != "id":
		get_viewport().msaa_3d = Viewport.MSAA_8X
	var tag := "%s_%s_%s" % [str(job["path"]), str(v[0]), pass_name]
	if job.has("arch"):
		tag = "arch%s_%s" % [str(job["arch"]), tag]
	if phase >= 0.0:
		tag = "gait%d_%s" % [int(job.get("gi", 0)), tag]
	await _save(tag)
	if pass_name == "id":
		_restore_ids(saved)
	_busy = false


func _save(tag: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "/" + tag + ".png")
	print("SHOT " + tag)
