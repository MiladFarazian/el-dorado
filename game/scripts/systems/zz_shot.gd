extends Node
## TEMPORARY screenshot harness for the M8 visual pass. Runs WINDOWED (not
## headless — rendering required):
##   godot -- --shot
## Parks a free camera at hand-picked vantages, hides every HUD layer, saves
## PNGs to the scratchpad, and quits. Delete after the art review.

## D-055: plates go to game/.gate/shots — gitignored, stable across sessions and agents.
## (Before this they went to one Claude session's scratchpad path, which Codex and the next
## session could not find.) Override with --shot-out=/abs/dir.
static var OUT_DIR := ProjectSettings.globalize_path("res://.gate/shots")  # gdlint:ignore=class-variable-name

var main_ref: Node = null
var _cam: Camera3D = null
var _f := 0
var _idx := 0
var _busy := false
# [name, camera pos, look-at, hour-of-day]
var _shots: Array = [
	["street_north", Vector3(193, 3.5, 470), Vector3(193, 12, 340), 13.0],
	# D-066: the two new districts, judged from the road a player arrives on.
	["fair_gate", Vector3(790.0, 3.0, 292.0), Vector3(846.0, 9.0, 305.0), 13.0],
	["fair_wheel_night", Vector3(904.0, 2.0, 322.0), Vector3(960.0, 24.0, 250.0), 21.5],
	["harvest_edge", Vector3(-800.0, 2.6, -395.0), Vector3(-805.0, 7.0, -480.0), 17.5],
	["tall_tom", Vector3(820.0, 3.0, 303.0), Vector3(868.0, 9.0, 258.0), 15.0],   # through the gate opening; the first try stood 1.5 m off a pylon
	# D-068: the loop's places.
	["boone_lot", Vector3(-146.0, 3.0, -18.0), Vector3(-110.0, 7.0, -72.0), 16.5],
	["cliff_boulevard", Vector3(-62.0, 6.5, 800.0), Vector3(-260.0, 5.0, 800.0), 17.0],
	["gilead_bottoms", Vector3(-492.0, 4.2, 838.0), Vector3(-430.0, 2.0, 762.0), 17.5],
	["skyline_from_freeway", Vector3(-60, 15, 2), Vector3(500, 46, 210), 16.5],
	["frontage_signs", Vector3(408, 3.4, 22), Vector3(414, 4.6, 44), 13.0],
	["trust_tower", Vector3(540, 60, 396), Vector3(451, 142, 305), 13.0],
	["billboard", Vector3(-652, 7.5, -34), Vector3(-672, 12, -56), 13.0],
	["aerial", Vector3(880, 300, 880), Vector3(300, 0, 230), 13.0],
	["street_night", Vector3(193, 3.5, 470), Vector3(193, 12, 340), 21.8],
	["skyline_night", Vector3(-60, 15, 2), Vector3(500, 46, 210), 21.8],
	["showcase_cars", Vector3(332, 3.4, 500), Vector3(332, 1.0, 522), 13.0],
	["hero_wrecker", Vector3(304.5, 2.1, 513.5), Vector3(313.5, 1.1, 522), 13.0],
	["hero_slab", Vector3(315.0, 1.7, 514.0), Vector3(323.5, 0.9, 522), 13.0],
	["hero_police", Vector3(360.0, 2.0, 514.5), Vector3(351.5, 1.0, 522), 13.0],
	["hero_pickup", Vector3(325.0, 2.3, 513.0), Vector3(333.5, 1.2, 522), 13.0],
	["showcase_people", Vector3(326.5, 1.62, 506.4), Vector3(327.5, 1.15, 511), 13.0],
	["hospital", Vector3(365, 2.2, 580), Vector3(365, 7.5, 622), 13.0],
	["hospital_night", Vector3(352, 1.9, 592), Vector3(367, 6.0, 616), 21.8],
	["street_detail", Vector3(287, 1.5, 476), Vector3(279, 0.4, 462), 13.0],
	["suburb_street", Vector3(-80, 22.0, -380), Vector3(-220, 0.0, -520), 13.0],
	["suburb_night", Vector3(-80, 22.0, -380), Vector3(-220, 0.0, -520), 21.8],
	["freeway_deck", Vector3(100, 12.5, 0), Vector3(260, 9.5, 0), 13.0],
	["freeway_night", Vector3(100, 12.5, 0), Vector3(260, 9.5, 0), 21.8],
	["floodway", Vector3(-672, -3.2, 560), Vector3(-696, -4.5, 470), 13.0],
	["plaza", Vector3(580, 3.2, 388), Vector3(580, 14.0, 336), 13.0],
	# Book stands at (324.2, _, 511.0) in the showcase line — aim AT him, from
	# just off his front-left shoulder (the M16 character agent found this
	# vantage was framing two random peds ~60 deg off-axis instead).
	["portrait", Vector3(322.6, 1.62, 508.6), Vector3(324.2, 1.35, 511.0), 13.0],
	# Judgement vantages: if a character can't survive THESE, it isn't done.
	# Car judgement vantages — the lineup sits at x 311..353, z 522, facing +Z.
	# A car that can't survive THESE isn't done. (Mirrors the face/side/back
	# discipline that finally fixed characters.)
	# QA cycle 1 (D-038) found these framed the WRONG THING: `car_side` was a
	# dead-astern rear view and `car_34` a rear-3/4, so the two bar rows that
	# name them (flank surface, cabin interior) had never actually been tested.
	# Re-aimed at the END car of the lineup (x=353) — the only one with clear
	# air on its +X side — and the lineup faces +Z, so front views come from +Z.
	["car_34", Vector3(359.5, 1.05, 528.6), Vector3(353.0, 0.75, 522.6), 13.0],
	["car_side", Vector3(361.5, 0.88, 522.2), Vector3(353.0, 0.74, 522.2), 13.0],
	["car_rear34", Vector3(359.5, 1.05, 515.8), Vector3(353.0, 0.75, 521.6), 13.0],
	# QA cycle 1: car_wheel was 4.4 m out (wheel ~60 px) — not a wheel shot.
	["car_wheel", Vector3(354.9, 0.50, 524.6), Vector3(353.9, 0.42, 523.9), 13.0],
	# QA cycle 1: the car set was re-aimed onto the Interceptor, so nothing
	# framed the Slab and D-007/D-009/D-039 were unverifiable. The Slab sits
	# at x=321.5; shoot it from -X where its neighbour is 10.5 m away.
	["slab_side", Vector3(313.0, 0.88, 521.8), Vector3(321.5, 0.74, 521.8), 13.0],
	["slab_34", Vector3(314.5, 1.02, 528.4), Vector3(321.5, 0.75, 522.4), 13.0],
	# Cycle 2: nothing in the set was dead astern of the Slab, so D-009 ("five
	# horizontal bands on the tail") was unverifiable. On the car's centreline.
	["slab_rear", Vector3(321.5, 0.92, 516.4), Vector3(321.5, 0.78, 521.6), 13.0],
	# CORRECTED cycle 4: the tree was innocent and so was the character. The
	# "orange canopy" is a screen-space veil painted by the REPO-TARGET BEACON
	# (repo_board.gd, a Y-billboarded emissive quad at world 338.6,0,528.0) —
	# proven three ways: its projected screen x (415 px) matches the tint peak
	# (417 px) to 2 px; a MultiMesh with ONE material and no instance colours
	# renders two different hues 58 px apart in the same frame; and the R-G
	# gradient is continuous across a single convex lobe, which no per-instance
	# colour can produce. All 425 canopy instances read R < G. So this vantage
	# was swung on a diagnosis that was never true — restored to the original
	# framing, which was correct.
	["face", Vector3(323.55, 1.62, 510.05), Vector3(324.2, 1.60, 511.0), 13.0],
	["torso", Vector3(323.0, 1.30, 509.6), Vector3(324.2, 1.15, 511.0), 13.0],
	["side", Vector3(322.0, 1.15, 511.05), Vector3(324.2, 1.05, 511.0), 13.0],
	["back", Vector3(324.2, 1.20, 513.2), Vector3(324.2, 1.10, 511.0), 13.0],
	["sky_wide", Vector3(300, 8, 500), Vector3(500, 90, 150), 13.0],
	["sky_night", Vector3(300, 8, 500), Vector3(500, 90, 150), 23.5],
	["landmark_church", Vector3(140, 4, 640), Vector3(140, 18, 720), 13.0],
	["landmark_stadium", Vector3(640, 6, 660), Vector3(640, 30, 760), 13.0],
	# M22 signage pass — one vantage per register, read from the distance the
	# sign is actually read from.
	["sg_marquee", Vector3(168, 3.0, 636), Vector3(168, 3.4, 652), 13.0],
	["sg_gigastead", Vector3(-260, 8.0, 330), Vector3(-260, 8.0, 430), 13.0],
	["sg_gigagate", Vector3(-230, 6.5, 366), Vector3(-230, 6.8, 391), 13.0],
	["sg_rooftops", Vector3(451, 120, 90), Vector3(451, 150, 330), 13.0],
	["sg_rooftops_night", Vector3(451, 120, 90), Vector3(451, 150, 330), 21.8],
	["sg_trust", Vector3(451, 150, 200), Vector3(451, 152, 305), 13.0],
	["sg_trust_night", Vector3(451, 150, 200), Vector3(451, 152, 305), 21.8],
	["sg_hosp_road", Vector3(352, 3.2, 560), Vector3(352, 7.6, 585), 13.0],
	["sg_gantry", Vector3(-90, 11.0, 4), Vector3(-200, 13.5, 4), 13.0],
	["sg_blade", Vector3(451, 4.6, 292), Vector3(451, 4.8, 305), 13.0],
	["sg_watertower", Vector3(-300, 34.0, -80), Vector3(-300, 36.9, -132), 13.0],
	["sg_ghost", Vector3(365, 22.0, 240), Vector3(365, 26.0, 300), 13.0],
	["sg_candyland", Vector3(-560, 6.0, 700), Vector3(-600, 0.5, 700), 13.0],
	# Face-on at the widest rooftop sign (ClingTel, 22.6 m roof) from 45 m.
	["sg_clingtel", Vector3(516.7, 122.5, 373.0), Vector3(485.4, 121.3, 340.6), 13.0],
	["sg_clingtel_night", Vector3(516.7, 122.5, 373.0), Vector3(485.4, 121.3, 340.6), 21.8],
	# D-041's own vantage: the sightline that stacked the two COUNTY GENERALs.
	["sg_hosp_stack", Vector3(324.0, 1.62, 510.0), Vector3(365.0, 12.0, 621.6), 13.0],
	["sg_hosp_drive", Vector3(365.0, 2.2, 556.0), Vector3(365.0, 8.0, 600.0), 13.0],
	["sg_payhut", Vector3(220.0, 2.2, 434.6), Vector3(213.1, 1.7, 434.6), 13.0],
	["sg_howdy", Vector3(451.0, 4.9, 318.0), Vector3(451.0, 4.7, 305.0), 13.0],
	["sg_storefront", Vector3(300.0, 4.0, 20.0), Vector3(300.0, 4.2, 44.0), 13.0],
]


## Object showcase: the five drivable profiles in a lineup, plus a row of
## factory people (Book front and centre). Built on the open street bed east
## of the smoke corridor; the shot run quits before anything matters.
func _build_mat_test() -> void:
	const PROFILES: Array[String] = [
		"res://data/vehicles/wrecker.json", "res://data/vehicles/slab.json",
		"res://data/vehicles/brisket.json", "res://data/vehicles/sedan.json",
		"res://data/vehicles/ai/police.json"]
	for i in PROFILES.size():
		var v := RaycastVehicle.new()
		v.profile_path = PROFILES[i]
		v.player_controlled = false
		main_ref.add_child(v)
		v.global_transform = Transform3D(Basis(Vector3.UP, PI),
			Vector3(311.0 + 10.5 * float(i), 1.2, 522.0))
	# M23 (skin6 finding 02): this row was ALWAYS built from character_factory,
	# so `face`/`torso`/`side`/`back`/`showcase_people` never showed the skinned
	# character even under `--skinned` — an entire wardrobe mission was judged at
	# vantages that could not display it. Pick the builder exactly as the four
	# gameplay call sites do (player_character/pedestrians/foot_cops/carjack).
	var factory: GDScript = load("res://scripts/world/character_factory.gd") \
		if OS.get_cmdline_user_args().has("--factory") \
		else load("res://scripts/world/skinned_character.gd")   # D-050 polarity
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260803
	for k in 7:
		var p := Node3D.new()
		main_ref.add_child(p)
		p.global_position = Vector3(325.6 + 1.3 * float(k), 0.05, 511.0)
		var cfg: Dictionary = factory.cop_config(rng) if k == 6 \
			else factory.random_config(rng)
		factory.build(p, cfg, 0.0)
	var book := Node3D.new()
	main_ref.add_child(book)
	book.global_position = Vector3(324.2, 0.05, 511.0)
	factory.build(book, factory.book_config(), 0.0)


func setup(main: Node) -> void:
	main_ref = main
	if not OS.get_cmdline_user_args().has("--shot"):
		set_process(false)
		return
	if DisplayServer.get_name() == "headless":
		# The dummy renderer never fires RenderingServer.frame_post_draw, so
		# _settle_and_save awaits a frame that never comes and the process sits
		# forever (one did, for 38 hours). Refuse loudly, same as perf_harness.
		push_error("SHOT: --shot needs a rendering window; --headless deadlocks the capture.")
		set_process(false)
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot-out="):
			OUT_DIR = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1600, 900))   # D-053: plates are 1600x900 regardless of the game window override
	# M24: `--shot-debug=normals|unshaded|lighting|overdraw` draws the whole
	# sweep through one of the viewport's debug views — the G-buffer normals or
	# the unshaded albedo answer "is it the mesh or the light?" in one plate.
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot-debug="):
			var mode := a.get_slice("=", 1)
			var dd := {"normals": Viewport.DEBUG_DRAW_NORMAL_BUFFER,
				"unshaded": Viewport.DEBUG_DRAW_UNSHADED,
				"lighting": Viewport.DEBUG_DRAW_LIGHTING,
				"overdraw": Viewport.DEBUG_DRAW_OVERDRAW}
			if dd.has(mode):
				get_viewport().debug_draw = dd[mode]
				print("SHOT debug view: ", mode)


func _process(_d: float) -> void:
	_f += 1
	if _f < 40 or _busy:
		return  # let the city, traffic, and dressing settle first
	if _idx == 0 and _cam == null:
		for n in (main_ref as Node).get_children():
			if n is CanvasLayer:
				(n as CanvasLayer).visible = false
		for sys: Node in (main_ref.get("systems") as Dictionary).values():
			for c in sys.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
		_build_mat_test()
		_cam = Camera3D.new()
		# D-080: Camera3D defaults to 75 deg VERTICAL fov, which at 16:9 is a
		# ~107 deg HORIZONTAL lens — at `car_side` that made the subject 19% of
		# frame width, so two bar rows named a vantage nothing could be judged
		# at. 40 deg vertical is a normal lens; subjects roughly triple.
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


var _token := 0   # D-054 watchdog: which vantage the pending coroutine belongs to


## WATCHDOG (D-054). One sweep on 2026-09-08 sat 13 minutes after `plaza` at
## 0.4% CPU with no error line — an await that never came back, once in three
## runs. A wedged sweep wedges the whole gate chain, so a vantage that has not
## saved in 12 s is reported with the engine's state and skipped; the stale
## coroutine, if it ever resumes, finds its token expired and does nothing.
func _watchdog(shot_name: String, tok: int) -> void:
	await get_tree().create_timer(12.0, true).timeout
	if tok != _token or not _busy:
		return
	print("SHOT STALL at %s: paused=%s max_fps=%d frames_drawn=%d process_frames=%d — skipping"
		% [shot_name, get_tree().paused, Engine.max_fps, Engine.get_frames_drawn(),
			Engine.get_process_frames()])
	_token += 1
	_idx += 1
	_busy = false


func _settle_and_save(shot_name: String) -> void:
	_token += 1
	var tok := _token
	_watchdog(shot_name, tok)
	for i in 8:  # let sky restyle + streaming settle
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if tok != _token:
		return   # the watchdog moved on without us
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + shot_name + ".png")
	if shot_name == "face":
		var sun_node: Node = main_ref.find_child("Sun", true, false)
		if sun_node is DirectionalLight3D:
			var to_sun: Vector3 = -(sun_node as DirectionalLight3D).global_transform.basis.z
			print("SHOT sun: toward-sun dir=%s elev=%.1f deg" % [to_sun, rad_to_deg(asin(to_sun.y))])
	print("SHOT saved: " + shot_name)
	_token += 1   # retire the watchdog for this vantage
	_idx += 1
	_busy = false
