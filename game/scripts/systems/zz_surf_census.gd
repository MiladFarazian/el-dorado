extends Node
## SURFACE CENSUS — permanent QA infrastructure (M23; was the Environment
## Artist's temporary aa_ssr_probe). Per D-032 every layer prints one boot census
## line; this one walks the tree ONCE at frame 30 and prints `SURFACES: materials=
## shaders= normalmapped= roughmapped= ...` so a boot log answers "did the
## material pass regress" without a screenshot. Inert in smoke mode.
##
##   (default)                print the SURFACES line at frame 30
##   --no-surf-census         suppress it
##   --surf-census-quit       print it and quit(0) — for scripted regression checks
##   --ssr-probe              (kept) force SSR/SDFGI/volfog on at runtime, frame 20
##   --surfshot=a,b,c         subset of the surface vantages (windowed only)
##   --surfshot-out=DIR       where the plates go
##   --winddiff               two frames 0.5 s apart at two flora vantages

const OUT_DEFAULT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/surf6/plates"

# name, cam pos, look-at, hour
const VANTAGES: Array = [
	["street_north", Vector3(193, 3.5, 470), Vector3(193, 12, 340), 13.0],
	["street_detail", Vector3(287, 1.5, 476), Vector3(279, 0.4, 462), 13.0],
	["street_night", Vector3(193, 3.5, 470), Vector3(193, 12, 340), 21.8],
	["skyline_night", Vector3(-60, 15, 2), Vector3(500, 46, 210), 21.8],
	["skyline_from_freeway", Vector3(-60, 15, 2), Vector3(500, 46, 210), 16.5],
	["trust_tower", Vector3(540, 60, 396), Vector3(451, 142, 305), 13.0],
	["plaza", Vector3(580, 3.2, 388), Vector3(580, 14.0, 336), 13.0],
	["freeway_deck", Vector3(100, 12.5, 0), Vector3(260, 9.5, 0), 13.0],
	["suburb_street", Vector3(-80, 22.0, -380), Vector3(-220, 0.0, -520), 13.0],
	["floodway", Vector3(-672, -3.2, 560), Vector3(-696, -4.5, 470), 13.0],
	["aerial", Vector3(880, 300, 880), Vector3(300, 0, 230), 13.0],
	["sg_storefront", Vector3(300.0, 4.0, 20.0), Vector3(300.0, 4.2, 44.0), 13.0],
	["hospital", Vector3(365, 2.2, 580), Vector3(365, 7.5, 622), 13.0],
	["sg_rooftops_night", Vector3(451, 120, 90), Vector3(451, 150, 330), 21.8],
	# flora-heavy, for the wind diff
	# Aimed at REAL instance origins read out of the live MultiMesh buffers
	# (--surf-where), not guessed off the map: a wind vantage with no grass in
	# frame measures traffic.
	["wild_flora", Vector3(-336.0, 0.85, 231.0), Vector3(-322.0, 0.55, 243.0), 13.0],
	["prairie_flora", Vector3(-136.0, 1.10, 276.0), Vector3(-123.0, 0.60, 288.0), 13.0],
	["mott_flora", Vector3(-614.0, 3.20, -124.0), Vector3(-596.0, 5.20, -106.0), 13.0],
]

var main_ref: Node = null
var _cam: Camera3D = null
var _f := 0
var _idx := 0
var _busy := false
var _out := OUT_DEFAULT
var _list: Array = []
var _mode := ""          # "" | "shot" | "wind"
var _census := false
var _census_quit := false
var _ssr := false
var _ssr_done := false


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return
	var args := OS.get_cmdline_user_args()
	_census = not args.has("--no-surf-census")
	_census_quit = args.has("--surf-census-quit")
	_ssr = args.has("--ssr-probe")
	var shot := _arg("--surfshot=")
	var wind := args.has("--winddiff")
	var od := _arg("--surfshot-out=")
	if od != "":
		_out = od
	if shot != "":
		_mode = "shot"
		for nm in shot.split(","):
			for v in VANTAGES:
				if v[0] == nm:
					_list.append(v)
	elif wind:
		_mode = "wind"
		for v in VANTAGES:
			if v[0] == "wild_flora" or v[0] == "prairie_flora" or v[0] == "mott_flora":
				_list.append(v)
	if _mode != "" and DisplayServer.get_name() == "headless":
		push_error("SURF: --surfshot/--winddiff need a rendering window.")
		_mode = ""
	if _mode == "" and not _census and not _ssr:
		set_process(false)
		return
	if _mode != "":
		DirAccess.make_dir_recursive_absolute(_out)


func _process(_d: float) -> void:
	_f += 1
	if _ssr and not _ssr_done and _f >= 20:
		_ssr_done = true
		_enable_ssr()
	if _census and _f == 30:
		_print_census()
		if OS.get_cmdline_user_args().has("--surf-where"):
			_where(get_tree().root)
		if _census_quit:
			get_tree().quit(0)
			return
	if _mode == "" or _busy or _f < 60:
		return
	if _idx == 0 and _cam == null:
		_hide_huds()
		_cam = Camera3D.new()
		_cam.fov = 40.0
		_cam.far = 4000.0
		add_child(_cam)
		_cam.make_current()
	if _idx >= _list.size():
		get_tree().quit(0)
		return
	_busy = true
	_take(_list[_idx])


func _enable_ssr() -> void:
	var we: Variant = main_ref.get("world_env")
	if not (we is WorldEnvironment):
		push_error("SURF: no world_env")
		return
	var env: Environment = (we as WorldEnvironment).environment
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_gi_inject = 1.0
	print("SSR PROBE: ssr+sdfgi+volfog enabled at runtime")


func _hide_huds() -> void:
	for n in (main_ref as Node).get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	for sys: Node in (main_ref.get("systems") as Dictionary).values():
		for c in sys.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = false


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
	img.save_png(_out + "/" + shot_name + ".png")
	print("SURF saved: " + shot_name)
	if _mode == "wind":
		# second plate 0.5 s later, same camera, same hour: only vertex
		# displacement can move a pixel between the two.
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png(_out + "/" + shot_name + "_b.png")
		print("SURF saved: " + shot_name + "_b")
	_idx += 1
	_busy = false



# ----------------------------- THE CENSUS ------------------------------------
func _print_census() -> void:
	var mats := {}
	var shaders := {}
	var normalmapped := 0
	var roughmapped := 0
	var std_nm := 0
	var std_rm := 0
	var std := 0
	var shd := 0
	var meshes := 0
	meshes = _walk(get_tree().root, mats, 0)
	for id in mats:
		var m: Material = mats[id]
		if m is ShaderMaterial:
			shd += 1
			var s: Shader = (m as ShaderMaterial).shader
			if s != null:
				shaders[s.get_instance_id()] = s
				var code := s.code
				if code.find("NORMAL_MAP") >= 0 or code.find("NORMAL =") >= 0:
					normalmapped += 1
				if code.find("ROUGHNESS =") >= 0:
					roughmapped += 1
		elif m is BaseMaterial3D:
			std += 1
			var b := m as BaseMaterial3D
			if b.normal_enabled and b.normal_texture != null:
				normalmapped += 1
				std_nm += 1
			if b.roughness_texture != null:
				roughmapped += 1
				std_rm += 1
	print("SURFACES: materials=%d shaders=%d normalmapped=%d roughmapped=%d standard=%d shadermat=%d geom=%d std_nm=%d std_rm=%d"
		% [mats.size(), shaders.size(), normalmapped, roughmapped, std, shd, meshes, std_nm, std_rm])


func _walk(n: Node, mats: Dictionary, meshes: int) -> int:
	if n is GeometryInstance3D:
		meshes += 1
		var gi := n as GeometryInstance3D
		_add(gi.material_override, mats)
		_add(gi.material_overlay, mats)
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					_add(mi.get_active_material(i), mats)
		elif gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				for i in mm.mesh.get_surface_count():
					_add(mm.mesh.surface_get_material(i), mats)
	for c in n.get_children():
		meshes = _walk(c, mats, meshes)
	return meshes


func _add(m: Material, mats: Dictionary) -> void:
	if m == null:
		return
	mats[m.get_instance_id()] = m
	if m.next_pass != null:
		_add(m.next_pass, mats)


## Where are the flora layers, actually? A vantage picked off the map is a
## guess; this prints real instance origins so the wind diff can be shot at a
## place that HAS grass in frame.
func _where(n: Node) -> void:
	if n is MultiMeshInstance3D:
		var nm := n.name
		if nm in ["GrassTufts", "Bluestem", "MottCanopies", "MesquiteCanopies",
				"Yucca", "Tumbleweeds", "PricklyPear", "MottTrunks",
				"MesquiteTrunks", "YuccaStalks", "FencePosts"]:
			var mm := (n as MultiMeshInstance3D).multimesh
			var c := mm.instance_count
			var mo := (n as MultiMeshInstance3D).material_override
			var cls := "NONE" if mo == null else \
				("ShaderMaterial:" + str(mo.get("shader").resource_name) \
				if mo is ShaderMaterial else mo.get_class())
			var s := "WHERE %s n=%d mat=%s:" % [nm, c, cls]
			for i in [0, c / 5, c / 2, (c * 4) / 5, c - 1]:
				if i >= 0 and i < c:
					var o := mm.get_instance_transform(i).origin
					s += " (%.0f,%.0f)" % [o.x, o.z]
			print(s)
	for c2 in n.get_children():
		_where(c2)
