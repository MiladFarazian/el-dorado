extends Node
## PERF HARNESS — the project's frame-time measurement rig.
##
## WHY THIS EXISTS. The quality bar has had a "60 fps at street level downtown"
## row since cycle 1 (§4b) and it had never once been run. Every performance
## claim in this project so far — including my own "120-140 fps" for the suburb
## lights — was an opinion with a number stapled to it. This file replaces all
## of them with a rig anybody can re-run, on demand, that prints the same table
## every time.
##
## IT IS INFRASTRUCTURE, NOT A THROWAWAY. `--suburb-perf` (suburb_night.gd) was
## a single-vantage, single-hour probe written to defend one change. This is its
## generalisation: N stations x 2 hours, one command, one table. The old flag
## still works and is left alone; use this one.
##
## ============================== HOW TO RUN ===================================
##   cd game/
##   godot -- --perf                      the whole matrix, table, quit
##   godot -- --perf --perf-only=downtown_night,hospital_night
##   godot -- --perf --perf-frames=600 --perf-warmup=150
##   godot -- --perf --perf-repeat=3      run the matrix 3x, report best + spread
##   godot -- --perf --perf-no-anchor     do NOT move the player (renderer-only)
##   godot -- --perf --perf-shot=DIR      also save a PNG of every station
##   godot -- --perf --perf-mm-audit      list every MultiMesh: count + shadow flag
##   godot -- --perf --perf-mm-noshadow   probe: force cast_shadow OFF on all of them
##   godot -- --perf --perf-mm-cast=A,B   probe: force cast_shadow back ON on named sets
##   godot -- --perf --perf-label-cut     probe: force ALPHA_CUT_DISCARD on all Label3D
##
## THE TWO PROBES ARE MEASUREMENT-ONLY AND DELIBERATELY NOT FIXES. A MultiMesh
## is frustum-culled as ONE unit, so a single instance visible to a directional
## shadow cascade drags the whole set into it, every frame, every cascade — and
## most of this project's instanced content (paint, decals, kerb ramps, trim,
## wires, sills, glazing, pools) has no business casting a shadow at all. Same
## story for `Label3D`: without `ALPHA_CUT_DISCARD` every sign sits in the
## sorted transparent pass. The layers that own that content belong to other
## agents, so this file MEASURES the win and hands the number over rather than
## reaching into somebody else's file. `--perf-mm-noshadow` is an UPPER BOUND:
## it strips building masses too, and those must keep their shadows.
## `--perf-shot` makes this a photometry rig as well as a frame-time rig: the
## same parked camera that produced the ms number produces the frame it
## measured, so a lighting change can be graded on both in one 25 s run instead
## of a 36-shot sweep. Pair it with `--perf-no-anchor` for a frame comparable to
## `zz_shot`'s (that harness does not move the player either, so the anchored
## run would park the wrecker in the middle of the shot).
## MUST RUN WINDOWED. `--headless` renders nothing, so every number would be a
## lie about an empty GPU. There is no headless mode here on purpose.
##
## ========================= WHAT IT MEASURES, AND WHY =========================
## Three clocks, because on this platform one of them is not trustworthy:
##  * FRAME  — wall-clock `_process` delta. This is the number a player feels.
##    It is also the number a compositor will happily flatten to the refresh
##    rate no matter what we ask of the display server, so the harness DETECTS
##    that (see `_capped`) and says so in the table instead of quietly shipping
##    a 60.0 fps that means "the monitor is 60 Hz".
##  * GPU    — `viewport_get_measured_render_time_gpu`, the renderer's own
##    timestamp-query result. A display cap cannot flatter it. **On the Metal
##    backend in Godot 4.7.1 this returns 0.00 for every frame** — the timestamp
##    query is not wired up. The harness detects an all-zero column and prints
##    `n/a` rather than a zero somebody could mistake for "free".
##  * CPU    — `viewport_get_measured_render_time_cpu`, the CPU cost of building
##    that frame's render commands. With GPU unavailable this is the only direct
##    renderer number we have, and it is a floor on renderer cost, not the whole.
## Reported per station: median / min / p95 / worst FRAME, median CPU, median
## draw calls, objects in frame, ambient population, and PIN% (below).
##
## WHICH WAY THE ERROR RUNS — read this before quoting an fps figure. A display
## that will not let go of vsync makes a frame LONGER (the engine waits to
## present); it can never make one shorter. So every FRAME number here is an
## UPPER bound on frame time and every fps figure is a LOWER bound. A station
## that passes 60 fps under a cap passes for real. The reverse does not hold:
## the headroom figures (120 fps, 180 fps) are floors and must not be quoted as
## the engine's ceiling.
##
## THE DEV MACHINE IS NOT A BENCH — why `--perf-repeat` exists. The first full
## matrix and an immediate re-run of two of its stations disagreed by 50 %
## (downtown_day 12.50 vs 8.33 ms; suburb_day 10.61 vs 5.38) on an IDENTICAL
## scene: same draw calls, same objects, same ambient population to within two
## peds. Nothing in the engine changed between them — a browser, a chat client
## and an editor did. A workstation at load average ~1.9 hands you a different
## answer every time you ask, so ONE RUN IS A MEASUREMENT OF THE AFTERNOON, not
## of the renderer. `--perf-repeat=N` runs the whole matrix N times and reports,
## per station, the BEST pass next to the SPREAD across passes. Best-of-N is not
## cherry-picking here: contention can only ever make a frame slower, so the
## fastest pass is the least-corrupted sample of the thing under test — and the
## worst pass is printed beside it so nobody has to take that on trust.
##
## PIN% is how much to distrust the headroom: the share of
## measured frames landing within 2% of the median. A free-running renderer
## scatters; a synchronised one does not.
##
## ===================== WHY THE PLAYER GETS TELEPORTED ========================
## `traffic.gd` spawns in a 70-260 m ring around THE PLAYER VEHICLE, and
## `pedestrians.gd` anchors on the player actor. Park a free camera in the
## suburb while the truck sits downtown and you measure an empty suburb: no
## cars, no peds, no police, a beautiful number and a false one. So each
## station teleports the player's rig to a ground anchor on real pavement
## inside that station's view, waits out the warm-up while the ambient
## population rebuilds, and reports the counts it actually achieved so a
## reviewer can see whether the load arrived. `--perf-no-anchor` turns this off
## for an A/B of pure renderer cost.
##
## ============================ HOUSE RULES ====================================
##  * Inert unless `--perf` is passed: no processing, no nodes, no allocation.
##  * Never runs in smoke mode and never touches the RNG, physics tuning, or
##    any material. It moves a camera, a clock, and one RigidBody.
##  * Day and night use the SAME camera per place, so the day->night delta is
##    attributable to lighting and nothing else.
##  * Weather is a random walk (`sky_weather.gd`) and is NOT pinned — pinning it
##    would be tuning the scene. It is REPORTED per row instead; a row that ran
##    under a storm says so and should be re-run.

const BOOT_SETTLE := 90              # frames before the first station: let the
                                     # city, dressing and traffic finish booting
const DEFAULT_WARMUP := 90           # per station, after the teleport
const DEFAULT_FRAMES := 300          # measured frames per station
const ANCHOR_SETTLE := 6             # frames between teleport and warm-up start

## [place, cam pos, look-at, ground anchor for the player's rig]
## Cameras are the QA screenshot vantages, so a perf row and a photometric row
## describe the same frame. Anchors are on real pavement: downtown on the
## street bed, suburb on a Stonebridle lane (pod x=-77.5, lane offset 21 m),
## freeway on the deck (top y 9.0), hospital on the ambulance apron.
const PLACES: Array = [
	["downtown", Vector3(193, 3.5, 470), Vector3(193, 12, 340), Vector3(193, 1.6, 470)],
	["suburb", Vector3(-80, 22.0, -380), Vector3(-220, 0.0, -520), Vector3(-98.5, 1.6, -424)],
	["freeway", Vector3(100, 12.5, 0), Vector3(260, 9.5, 0), Vector3(100, 10.2, 5.0)],
	["hospital", Vector3(352, 1.9, 592), Vector3(367, 6.0, 616), Vector3(352, 1.6, 599)],
	# THE POST-DEATH FRAME. Not a screenshot vantage — it is the one view no
	# player can avoid, and no harness in the project had ever framed it. Derived
	# from the respawn contract rather than picked by eye: on_foot.gd:243 puts
	# the avatar on greybox_city's HOSPITAL_DOOR facing -Z and calls
	# chase_camera.snap_foot_rig(0), which places the lens at pivot(+1.65 head)
	# - forward*4.0 + 0.4 up and aims 8 m ahead. That lands the camera inside
	# the ER wing (greybox_city.gd:630, a solid box spanning z 612..624), where
	# `chase_camera._spring` pulls it back to just outside the glass. Standing
	# the station AT the raw computed position measured mean 0.94 — the inside
	# of a windowless box — which is a good reminder that a vantage nobody has
	# ever rendered is a vantage nobody has ever checked. It sits at the glass
	# (z 611.4, the door face is 612.05) and looks out across the apron, which
	# is what the player sees. The anchor is greybox_city's HOSPITAL_TRUCK,
	# where the wrecker really waits, so the frame contains what it contains.
	["hospital_door", Vector3(365, 2.20, 611.4), Vector3(365, 1.80, 599.4),
		Vector3(349, 1.2, 605)],
]
## Hours. 13.0 is the noon-ish shot hour; 21.8 is the night hour every night
## vantage and every photometric measurement in the defect ledger uses.
const HOURS: Array = [["day", 13.0], ["night", 21.8]]

## A frame budget of 16.67 ms is 60 fps. Anything at or under this passes §4b.
const BUDGET_MS := 1000.0 / 60.0

var main_ref: Node = null
var _on := false
var _cam: Camera3D = null
var _frame := 0
var _idx := 0                        # station index
var _phase := 0                      # 0 enter, 1 settle+warmup, 2 measure
var _n := 0
var _warmup := DEFAULT_WARMUP
var _frames := DEFAULT_FRAMES
var _anchor_on := true
var _stations: Array = []            # [name, campos, look, hour, anchor]
var _rows: Array = []                # finished station results (Dictionary)
var _f_ms := PackedFloat32Array()
var _gpu_ms := PackedFloat32Array()
var _cpu_ms := PackedFloat32Array()
var _draws := PackedInt32Array()
var _objs := PackedInt32Array()
var _t0 := 0
var _boot_ms := 0                    # engine start -> first rendered frame
var _shot_dir := ""                  # --perf-shot=DIR, "" disables
var _busy := false                   # a save is awaiting frame_post_draw
var _repeat := 1                     # matrix passes
var _pass := 0
var _mm_audit := false
var _mm_noshadow := false
var _mm_cast := PackedStringArray()  # --perf-mm-cast=A,B: force these back ON
var _mm_restored := 0
var _probe_only := false             # --perf-mm-cast without --perf (see setup)
var _label_cut := false


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_process(false)
		return
	var args := OS.get_cmdline_user_args()
	_on = args.has("--perf")
	if not _on:
		# PROBE-ONLY MODE. `--perf-mm-cast=` is allowed without `--perf` so the
		# SCREENSHOT harness can be A/B'd too: `godot -- --shot` and
		# `godot -- --shot --perf-mm-cast=A,B` render the same 39 vantages under
		# two shadow policies FROM ONE TREE, which is the only honest way to
		# compare frames when other agents are editing the project the same
		# hour (a camera change landed mid-cycle-3 and silently invalidated a
		# before/after set taken 20 minutes apart).
		for a0 in args:
			if a0.begins_with("--perf-mm-cast="):
				_mm_cast = a0.substr(15).split(",", false)
		if _mm_cast.size() > 0 and DisplayServer.get_name() != "headless":
			_probe_only = true
			return                   # _process applies it on frame 3, then stops
		set_process(false)           # the entire cost of this file in a normal run
		return
	if DisplayServer.get_name() == "headless":
		push_error("PERF: --perf needs a rendering window; --headless measures nothing.")
		set_process(false)
		return
	var only := PackedStringArray()
	for a in args:
		if a.begins_with("--perf-only="):
			only = a.substr(12).split(",", false)
		elif a.begins_with("--perf-frames="):
			_frames = maxi(30, int(a.substr(14)))
		elif a.begins_with("--perf-warmup="):
			_warmup = maxi(10, int(a.substr(14)))
		elif a == "--perf-no-anchor":
			_anchor_on = false
		elif a.begins_with("--perf-shot="):
			_shot_dir = a.substr(12)
		elif a.begins_with("--perf-repeat="):
			_repeat = clampi(int(a.substr(14)), 1, 20)
		elif a == "--perf-mm-audit":
			_mm_audit = true
		elif a == "--perf-mm-noshadow":
			_mm_noshadow = true
		elif a.begins_with("--perf-mm-cast="):
			_mm_cast = a.substr(15).split(",", false)
		elif a == "--perf-label-cut":
			_label_cut = true
	for p: Array in PLACES:
		for h: Array in HOURS:
			var nm: String = "%s_%s" % [p[0], h[0]]
			if only.size() > 0 and not only.has(nm):
				continue
			_stations.append([nm, p[1], p[2], float(h[1]), p[3]])
	if _stations.is_empty():
		push_error("PERF: --perf-only matched no station.")
		set_process(false)
		return
	# Ask for an uncapped presentation. Whether we GET one is a platform
	# question, which is why `_capped` exists and why the table prints GPU/CPU
	# next to FRAME rather than instead of it.
	# MEASUREMENT WINDOW (D-053). project.godot ships a 1280x720 window override
	# over the 1600x900 canvas (Codex, 2026-09-06, for the default game window);
	# with stretch=canvas_items the 3D view renders at the WINDOW size, so every
	# frame time would silently be measured on 36% fewer pixels than bar §4b's
	# 1600x900. The harness pins its own window; the printed size below proves it.
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_t0 = Time.get_ticks_msec()


func _process(delta: float) -> void:
	_frame += 1
	if _probe_only:
		# Apply the shadow-policy A/B and get out of the way — no camera, no
		# timing, no HUD changes. Frame 3 so every world layer has built.
		if _frame < 3:
			return
		_walk(main_ref)
		print("PERF PROBE: cast_shadow forced back ON on %d/%d named "
			% [_mm_restored, _mm_cast.size()]
			+ "MultiMeshInstance3D — A/B against a previous shadow policy")
		set_process(false)
		return
	if _frame == 1:
		# §4b row 2, "Boot to playable <= 20 s", which has also never been run.
		# Time.get_ticks_msec() counts from engine start, and frame 1 of _process
		# is the first frame after the whole tree built and drew: that is the
		# moment the player has a controllable game.
		_boot_ms = Time.get_ticks_msec()
	if _frame < BOOT_SETTLE:
		return
	if _cam == null:
		_begin()
		return
	if _busy:
		return                       # a screenshot is awaiting frame_post_draw
	if _idx >= _stations.size():
		_pass += 1
		if _pass < _repeat:
			_idx = 0                 # another pass over the same matrix
			_phase = 0
			return
		_report()
		get_tree().quit(0)
		return
	var st: Array = _stations[_idx]
	_pin_clock(float(st[3]))
	if _phase == 0:
		_enter(st)
		_phase = 1
		_n = 0
		return
	_n += 1
	if _phase == 1:
		if _n < ANCHOR_SETTLE + _warmup:
			return
		_phase = 2
		_f_ms.clear(); _gpu_ms.clear(); _cpu_ms.clear()
		_draws.clear(); _objs.clear()
		return
	var vp := get_viewport().get_viewport_rid()
	_f_ms.append(delta * 1000.0)
	_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
	_draws.append(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_objs.append(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	if _f_ms.size() >= _frames:
		_finish(st)
		_idx += 1
		_phase = 0
		if _shot_dir != "":
			_save_shot(str(st[0]))   # async; _busy holds the camera in place


## One-time setup: kill every HUD (a dev overlay is not the frame under test),
## turn on the renderer's timestamp queries, and park a free camera.
func _begin() -> void:
	for n in (main_ref as Node).get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	var sysv: Variant = main_ref.get("systems")
	if sysv is Dictionary:
		for s: Node in (sysv as Dictionary).values():
			for c in s.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	if _mm_audit or _mm_noshadow or _label_cut or _mm_cast.size() > 0:
		_walk(main_ref)
		if _mm_audit:
			_mm_report()
		if _mm_cast.size() > 0:
			print("PERF PROBE: cast_shadow forced back ON on %d/%d named "
				% [_mm_restored, _mm_cast.size()]
				+ "MultiMeshInstance3D — A/B against a previous shadow policy")
		if _mm_noshadow:
			print("PERF PROBE: cast_shadow forced OFF on %d/%d MultiMeshInstance3D "
				% [_mm_stripped, _mm_seen]
				+ "(%d instances) — UPPER BOUND, masses stripped too" % _mm_inst)
		if _label_cut:
			print("PERF PROBE: ALPHA_CUT_DISCARD forced on %d/%d Label3D"
				% [_lbl_stripped, _lbl_seen])
	RenderingServer.viewport_set_measure_render_time(
		get_viewport().get_viewport_rid(), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_cam = Camera3D.new()
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	var vs := DisplayServer.window_get_vsync_mode()
	var sz := DisplayServer.window_get_size()
	print("PERF HARNESS: %d stations x (%d warmup + %d measured) frames, "
		% [_stations.size(), _warmup, _frames]
		+ "%dx%d, vsync=%s, anchor=%s, driver=%s"
		% [sz.x, sz.y, "DISABLED" if vs == DisplayServer.VSYNC_DISABLED else str(vs),
			"on" if _anchor_on else "OFF",
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))])


## Enter a station: aim the camera, teleport the player's rig onto the anchor so
## the ambient systems follow, and let it settle.
func _enter(st: Array) -> void:
	_cam.global_position = st[1]
	_cam.look_at(st[2], Vector3.UP)
	if _anchor_on:
		_anchor(st[4])


func _anchor(pos: Vector3) -> void:
	var v: Variant = main_ref.get("vehicle")
	if not (v is Node3D) or not is_instance_valid(v):
		return
	var body := v as Node3D
	var xf := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), pos)
	if body.has_method("reset_to"):
		body.call("reset_to", xf)
	else:
		body.global_transform = xf


## sky_weather advances its own clock every physics tick; hold the station's
## hour so the lighting under test is the lighting we asked for.
func _pin_clock(hour: float) -> void:
	var sky := _sky()
	if sky != null:
		sky.set("time_of_day", hour)


func _sky() -> Node:
	var sysv: Variant = main_ref.get("systems")
	if not (sysv is Dictionary):
		return null
	var s: Variant = (sysv as Dictionary).get("sky_weather")
	return s as Node if (s is Node and is_instance_valid(s)) else null


func _finish(st: Array) -> void:
	var f := _sorted(_f_ms)
	var g := _sorted(_gpu_ms)
	var c := _sorted(_cpu_ms)
	var d := _sorted_i(_draws)
	var o := _sorted_i(_objs)
	var n := f.size()
	var med: float = f[n / 2]
	var pinned := 0
	for s: float in f:
		if absf(s - med) <= med * 0.02:
			pinned += 1
	var row := {
		"name": str(st[0]),
		"f_med": med, "f_p95": f[mini(int(n * 0.95), n - 1)], "f_max": f[n - 1],
		"f_min": f[0],
		"pin": 100.0 * float(pinned) / float(n),
		"gpu": g[n / 2], "cpu": c[n / 2],
		"gpu_ok": g[n - 1] > 0.0,          # backend reports GPU time at all?
		"draws": d[n / 2], "objs": o[n / 2],
		"pos": _player_pos(),
		# "towable" is the project's catch-all for every hookable body — ambient
		# traffic, parked stock, junkers and cruisers all carry it, so it is the
		# honest "how many vehicles are alive around this station" number.
		"cars": _count("towable") + _count("police"),
		"peds": _count("pedestrian") + _count("officer"),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"storm": _weather(),
	}
	_rows.append(row)
	print(("PERF %-16s frame med %6.2f ms (%5.1f fps)  min %5.2f  p95 %6.2f  "
		+ "worst %6.2f  pin %3.0f%% | cpu %5.2f | draws %5d objs %5d | "
		+ "cars %2d peds %2d | %s | rig at %v")
		% [row["name"], row["f_med"], 1000.0 / maxf(row["f_med"], 0.001),
			row["f_min"], row["f_p95"], row["f_max"], row["pin"], row["cpu"],
			row["draws"], row["objs"], row["cars"], row["peds"], row["storm"],
			row["pos"]])


## Photograph the frame we just measured. The camera has not moved and will not
## until `_busy` clears, so the PNG is the same view the milliseconds came from.
func _save_shot(nm: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir.path_join(nm + ".png"))
	print("PERF SHOT: " + nm)
	_busy = false


func _count(group: String) -> int:
	return get_tree().get_nodes_in_group(group).size()


# ===================== MULTIMESH / LABEL SHADOW PROBES =======================
var _mm_seen := 0
var _mm_stripped := 0
var _mm_inst := 0
var _lbl_seen := 0
var _lbl_stripped := 0
var _mm_rows: Array = []             # [path, instances, was_casting]


## One walk of the whole tree, serving the audit and both probes.
func _walk(n: Node) -> void:
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var count := mmi.multimesh.instance_count if mmi.multimesh != null else 0
		var casting := mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mm_seen += 1
		_mm_rows.append([str(mmi.get_parent().name) + "/" + str(mmi.name),
			count, casting])
		if casting and _mm_noshadow:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mm_stripped += 1
			_mm_inst += count
		elif not casting and _mm_cast.has(str(mmi.name)):
			# A/B without a VCS: name the sets a previous policy had casting and
			# this run reproduces that policy exactly, so "before" and "after"
			# can be interleaved minutes apart on a machine whose absolute frame
			# times drift 40% between runs. See docs/tech/rendering/perf-harness.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_mm_restored += 1
	elif n is Label3D and _label_cut:
		var l := n as Label3D
		_lbl_seen += 1
		if l.alpha_cut != Label3D.ALPHA_CUT_DISCARD:
			l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
			_lbl_stripped += 1
	for c in n.get_children():
		_walk(c)


## The worklist an owner needs: which of their MultiMeshes are dragging their
## whole instance set through every directional shadow cascade, and how big.
func _mm_report() -> void:
	_mm_rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var casting_inst := 0
	var total_inst := 0
	print("\n---------------- MULTIMESH SHADOW AUDIT ----------------")
	print("| instances | casts | node |")
	for r: Array in _mm_rows:
		total_inst += int(r[1])
		if bool(r[2]):
			casting_inst += int(r[1])
		print("| %9d |  %-3s  | %s" % [r[1], "YES" if r[2] else "no", r[0]])
	print("%d MultiMeshes, %d instances, %d of them (%.0f%%) in every shadow cascade"
		% [_mm_seen, total_inst, casting_inst,
			100.0 * float(casting_inst) / maxf(float(total_inst), 1.0)])
	print("-------------------------------------------------------\n")


## Where the player's rig actually ended up. Printed so a reviewer can see the
## anchor took and the body did not sink, launch, or stay downtown — an anchor
## that silently failed would quietly delete the ambient load from the row.
func _player_pos() -> Vector3:
	var v: Variant = main_ref.get("vehicle")
	if v is Node3D and is_instance_valid(v):
		return (v as Node3D).global_position.round()
	return Vector3.ZERO


func _weather() -> String:
	var sky := _sky()
	if sky == null:
		return "?"
	return "STORM" if bool(sky.get("is_storm")) else "clear"


func _sorted(src: PackedFloat32Array) -> Array:
	var a := Array(src)
	a.sort()
	return a


func _sorted_i(src: PackedInt32Array) -> Array:
	var a := Array(src)
	a.sort()
	return a


## Presentation-sync detection, without a GPU clock to lean on. A free-running
## renderer's frame times scatter; a synchronised one lands on the same value
## over and over. PIN >= 85% of frames inside +-2% of the median is a
## presentation cadence, not a coincidence — so the headroom on that row is a
## FLOOR and the true frame time is somewhere below it.
func _capped(r: Dictionary) -> bool:
	return float(r["pin"]) >= 85.0


func _report() -> void:
	var secs := float(Time.get_ticks_msec() - _t0) / 1000.0
	var gpu_ok := false
	for r: Dictionary in _rows:
		gpu_ok = gpu_ok or bool(r["gpu_ok"])
	# Group the passes by station, keeping first-seen order.
	var order: Array[String] = []
	var by_name := {}
	for r: Dictionary in _rows:
		var nm: String = r["name"]
		if not by_name.has(nm):
			by_name[nm] = []
			order.append(nm)
		(by_name[nm] as Array).append(r)
	print("\n=========================== FPS BASELINE ===========================")
	print("| station            | best ms |  fps  | p95 ms | worst | spr% | pin% | cpu ms | gpu ms | draws | objs | cars | peds | 60fps |")
	print("|--------------------|---------|-------|--------|-------|------|------|--------|--------|-------|------|------|------|-------|")
	var any_cap := false
	var fails: Array[String] = []
	var contended: Array[String] = []
	for nm in order:
		var passes: Array = by_name[nm]
		var best: Dictionary = passes[0]
		var worst_med: float = float(best["f_med"])
		var worst_frame: float = float(best["f_max"])
		var worst_p95: float = float(best["f_p95"])
		for r: Dictionary in passes:
			if float(r["f_med"]) < float(best["f_med"]):
				best = r
			worst_med = maxf(worst_med, float(r["f_med"]))
			worst_frame = maxf(worst_frame, float(r["f_max"]))
			worst_p95 = maxf(worst_p95, float(r["f_p95"]))
		var bm: float = float(best["f_med"])
		var spread: float = 100.0 * (worst_med - bm) / maxf(bm, 0.001)
		any_cap = any_cap or _capped(best)
		var pass_60: bool = float(best["f_p95"]) <= BUDGET_MS
		if not pass_60:
			fails.append(nm)
		elif worst_p95 > BUDGET_MS:
			contended.append(nm)
		print("| %-18s | %7.2f | %5.1f | %6.2f | %5.2f | %4.0f | %4.0f | %6.2f | %6s | %5d | %4d | %4d | %4d | %s |"
			% [nm, bm, 1000.0 / maxf(bm, 0.001), best["f_p95"], worst_frame,
				spread, best["pin"], best["cpu"],
				("%.2f" % float(best["gpu"])) if gpu_ok else "n/a",
				best["draws"], best["objs"], best["cars"], best["peds"],
				"  ok  " if pass_60 else " FAIL "])
	print("--------------------------------------------------------------------")
	print("%d pass(es) per station. 'best' = fastest pass's median (the least-"
		% _repeat)
	print("  contended sample); 'spr%' = how much the slowest pass was worse;")
	print("  'worst' = worst single frame across ALL passes.")
	if not gpu_ok:
		print("GPU COLUMN IS n/a: this backend (%s) reported 0.00 ms for every"
			% RenderingServer.get_video_adapter_api_version())
		print("  frame. Godot 4.7.1's Metal backend does not implement the viewport")
		print("  GPU timestamp query. CPU ms is renderer CPU only, NOT total cost.")
	if any_cap:
		print("PRESENTATION-SYNC on one or more rows (pin >= 85%): the frame time is")
		print("  a cadence, not a measurement of work. Read those rows as an UPPER")
		print("  bound on frame time / LOWER bound on fps. A 60 fps PASS still holds")
		print("  (a sync can only lengthen a frame); the HEADROOM figure does not.")
	print("BOOT TO PLAYABLE: %.2f s (bar §4b: <= 20 s) — %s"
		% [float(_boot_ms) / 1000.0, "ok" if _boot_ms <= 20000 else "FAIL"])
	if fails.is_empty():
		print("VERDICT: every station holds the 16.67 ms / 60 fps budget at p95.")
	else:
		print("VERDICT: p95 OVER BUDGET at: " + ", ".join(fails))
	if not contended.is_empty():
		print("UNDER CONTENTION ONLY (best pass passes, a slower pass did not): "
			+ ", ".join(contended))
		print("  Not an engine defect on its own — but it is how close to the")
		print("  budget these stations run once anything else wants the machine.")
	print("Run: %.1f s wall, %d frames measured per station, %dx%d, msaa_3d=%s."
		% [secs, _frames, DisplayServer.window_get_size().x,
			DisplayServer.window_get_size().y,
			str(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))])
	print("=============================================================")
