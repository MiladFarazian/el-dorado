extends Node
## SUBURB NIGHT LIGHTS (D-014) — the runtime light manager for Stonebridle
## Ranch and the north fringe.
##
## THE DEFECT. QA measured the ground half of `suburb_night` at mean luminance
## 2.52/255 with 100% of pixels under 8/255: a mathematically black void next to
## a daytime read of 182. The cause was not exposure. The suburb owned no
## Light3D of any kind — the porch fixtures and lit panes were EMISSIVE QUADS,
## which are seen but light nothing, so every wall, roof, driveway, fence and
## yard in the district rendered at zero. sky_weather's night sun sits 35 deg
## BELOW the horizon at 21:48, so it illuminates no up-facing surface, and
## ambient is sourced from a night sky that is itself near-black. Nothing was
## going to lift that except real local lights.
##
## THE READ WE ARE AFTER, and what draws it:
##   warm porch light on every house        -> PORCH  omni, 14.5 m, no shadow
##   a driveway floodlight here and there   -> FLOOD  omni, 15.5 m, cool white
##   blue TV flicker behind a curtain       -> TV     omni, 5.5 m, animated
##   a streetlight at the corners           -> HEAD   omni on the cobra heads
##                                             city_dressing already publishes
##   everything else falling to blue-black  -> nothing. Contrast is the point.
## Downtown must still be the bright district; the target is a suburb that is
## clearly a PLACE and still clearly darker and lonelier than the grid.
##
## ============================= THE BUDGET ====================================
## Hundreds of shadow-casting lights would wreck the frame. So:
##  * NO shadows on any light in this file, ever. Not one shadow map.
##  * Every light distance-fades and is CULLED past begin+length, so what
##    costs anything is how many are in range at once, not how many exist.
##    Porch lights die at 240 m, floods at 270 m, TVs at 135 m, heads at 360 m.
##    Past those ranges the district is carried by emissive fixtures and by
##    streetlight_glow's decal pools — a deliberate lighting LOD chain.
##  * Per frame this system does ONE float compare. The dusk/dawn ramp walks a
##    sorted array from a moving index and switches only the lights actually
##    crossing their threshold this frame: amortised O(1), never O(lights). A
##    teleported clock (the --shot harness) costs one full pass, once.
##  * TV flicker touches a FIXED cap of lights (TV_CAP) every third frame. It
##    is a constant, not a function of district size.
##  * The flicker waveform is a pure function of the game clock, so screenshot
##    regression tests reproduce.
##
## TOGGLES (working convention: every visual feature ships with one)
##   --no-suburb-lights   build nothing; the district reverts to the old read
##   --suburb-perf        park at the suburb_night vantage, measure frame time
##                        over PERF_FRAMES, print percentiles, quit
## and a profiler line is printed at build in every run.
##
## OWNERSHIP: creates only OmniLight3D nodes under one container. Touches no
## geometry, no collision, no RNG stream, and nothing in smoke mode.

const GLOW := preload("res://scripts/systems/streetlight_glow.gd")

# --- Porch: warm incandescent over the front door. Energy is set by the
# BRIGHTEST thing it can hit — the 0.87 cream door trim, standing 0.85 m proud
# of it — against main.gd's 1.05 glow_hdr_threshold. Including the cosine term
# the trim reads 1.30 directly behind the fixture, 1.11 at 0.5 m along the wall
# and 0.82 at 1.0 m: a ~0.6 m halo on the siding, which is what a porch light
# does, and no hazing anywhere else. Brick (0.50) and the garage door (0.78)
# can never reach the threshold at this energy at all. The wide range and slack
# attenuation are what turn the fixture from a hotspot into a wash on the yard.
const PORCH_COL := Color(1.0, 0.72, 0.40)
const PORCH_E := 1.55
const PORCH_R := 14.5
const PORCH_ATT := 0.65              # generous: a wash, not a hotspot
# --- Driveway flood: cool halogen on the garage header. Capped by the 0.78
# garage door 1.2 m below it.
const FLOOD_COL := Color(0.92, 0.94, 1.0)
const FLOOD_E := 1.50
const FLOOD_R := 15.5
const FLOOD_ATT := 0.75
# --- TV: blue spill through one lit pane.
const TV_COL := Color(0.52, 0.66, 1.0)
const TV_E := 0.95
const TV_R := 5.5
const TV_ATT := 1.30
const TV_CAP := 40                   # hard ceiling on animated lights
const TV_RATE := 0.030               # rad per GAME second (~4.3 Hz real time)
const TV_SWING := 0.42               # +-42% around TV_E; small on purpose so a
                                     # screenshot's photometry barely moves
const TV_EVERY := 3                  # animate on every Nth frame
# --- Cobra heads: the suburb's own streetlights, from the dressing peer.
const HEAD_COL := Color(1.0, 0.84, 0.52)
const HEAD_E := 2.4
const HEAD_R := 24.0
const HEAD_ATT := 1.10
const HEAD_DROP := 0.35              # light hangs just under the lens
const SUBURB_Z_MAX := -180.0         # SUB_RECT ends here; heads south of it
                                     # are downtown's and already have a read
# --- Distance fade (begin, length). Culled at begin+length. This is the LOD
# chain and it was measured, not guessed. The suburb_night vantage stands 22 m
# up and its ground half spans 23-200 m of ground, so the first pass's 130 m
# cull left the far HALF of the district unlit and the frame measured 8.92
# mean. Pushed out to a 240 m cull it measures 9.87 and the whole vista reads.
# The cost is bounded by geometry, not by the array size: a 240 m frustum wedge
# of a plat holding 245 houses across 91 hectares holds ~15 houses, so ~25
# lights are ever live at this vantage and ~15 driving the lanes. Measured
# delta at the vantage: +1.2 to +2.3 ms, 120-140 fps against a 60 fps bar.
const FADE_PORCH := Vector2(170.0, 70.0)
const FADE_FLOOD := Vector2(190.0, 80.0)
const FADE_TV := Vector2(95.0, 40.0)
const FADE_HEAD := Vector2(260.0, 100.0)
const SPECULAR := 0.35               # window glass is metallic 0.22 / rough
                                     # 0.16; full specular put hard dots on it
# --- Dusk stagger: nobody's porch light comes on at the same second.
const STAGGER := 0.55                # fraction of the dusk ramp spent switching
# --- --suburb-perf harness (mirrors zz_shot's suburb_night vantage exactly).
const PERF_POS := Vector3(-80, 22.0, -380)
const PERF_LOOK := Vector3(-220, 0.0, -520)
const PERF_HOUR := 21.8
const PERF_WARMUP := 90
const PERF_FRAMES := 420

var main_ref: Node = null
var _sky: Node = null
var _root: Node3D = null
# Ramped lights, SORTED by turn-on threshold ascending. _on is how many of the
# prefix are currently visible; the ramp only ever moves that index.
var _ramp: Array[OmniLight3D] = []
var _thresh := PackedFloat32Array()
var _on := 0
var _cur := -1.0
# Animated lights: a fixed-size set, updated on a fixed cadence.
var _tv: Array[OmniLight3D] = []
var _tv_phase := PackedFloat32Array()
var _frame := 0
var _dress: Node = null              # suburb_dressing, for its emissive dimmer
var _counts := Vector4i.ZERO         # porch, flood, tv, head — for the report
# perf harness state
var _perf := false
var _perf_cam: Camera3D = null
var _perf_n := 0
var _perf_ms := PackedFloat32Array()   # GPU render ms per frame
var _perf_cpu := PackedFloat32Array()  # CPU render ms per frame


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_process(false)
		return
	var args := OS.get_cmdline_user_args()
	_perf = args.has("--suburb-perf")
	if _perf:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if args.has("--no-suburb-lights"):
		print("SUBURB NIGHT: disabled (--no-suburb-lights)")
		# Still process when profiling — the toggle exists so the A/B can be
		# MEASURED, and a toggle you cannot profile against is decoration.
		set_process(_perf)
		return
	_build()


# ============================== BUILD ========================================
func _build() -> void:
	var city: Variant = main_ref.get("city")
	if not (city is Node3D) or not is_instance_valid(city):
		set_process(false)
		return
	var host := city as Node3D
	_dress = host.get_node_or_null("suburb_dressing")
	var t0 := Time.get_ticks_usec()
	_root = Node3D.new()
	_root.name = "SuburbNightLights"
	host.add_child(_root)
	var porch := _points(_dress, "get_porch_light_points")
	var flood := _points(_dress, "get_flood_light_points")
	var tvs := _points(_dress, "get_tv_light_points")
	var heads := _suburb_heads(host)
	# Build unsorted with their thresholds, then sort once.
	var pairs: Array = []
	for p in porch:
		pairs.append([_stagger(p), _light(p, PORCH_COL, PORCH_E, PORCH_R,
			PORCH_ATT, FADE_PORCH)])
	for p2 in flood:
		pairs.append([_stagger(p2), _light(p2, FLOOD_COL, FLOOD_E, FLOOD_R,
			FLOOD_ATT, FADE_FLOOD)])
	for p3 in heads:
		# Street lighting is on a photocell, not a householder: it comes up
		# early and together, so it leads the porch lights.
		pairs.append([0.02, _light(p3, HEAD_COL, HEAD_E, HEAD_R, HEAD_ATT,
			FADE_HEAD)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_thresh.resize(pairs.size())
	_ramp.resize(pairs.size())
	for i in pairs.size():
		_thresh[i] = pairs[i][0]
		_ramp[i] = pairs[i][1]
	for p4 in tvs:
		if _tv.size() >= TV_CAP:
			break
		var l := _light(p4, TV_COL, TV_E, TV_R, TV_ATT, FADE_TV)
		_tv.append(l)
		_tv_phase.append(_stagger(p4) * TAU)
	_counts = Vector4i(porch.size(), flood.size(), _tv.size(), heads.size())
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print(("SUBURB NIGHT: %d lights (porch %d, flood %d, tv %d, head %d), "
		+ "0 shadow maps, built in %.1f ms") % [_ramp.size() + _tv.size(),
		_counts.x, _counts.y, _counts.z, _counts.w, ms])
	if _ramp.is_empty() and _tv.is_empty() and not _perf:
		set_process(false)


func _points(peer: Node, method: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if peer == null or not is_instance_valid(peer) or not peer.has_method(method):
		return out
	var got: Variant = peer.call(method)
	if not (got is Array):
		return out
	for v: Variant in (got as Array):
		if v is Vector3 and (v as Vector3).is_finite():
			out.append(v as Vector3)
	return out


## The cobra heads city_dressing publishes, filtered to the ones standing in
## the suburb. Downtown's heads are left alone: that district already measures
## 18.78 and does not need more lights in it.
func _suburb_heads(host: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var d := host.get_node_or_null("CityDressing")
	if d == null or not d.has_method("get_streetlight_head_xfs"):
		return out
	var got: Variant = d.call("get_streetlight_head_xfs")
	if not (got is Array):
		return out
	for v: Variant in (got as Array):
		if not (v is Transform3D):
			continue
		var o := (v as Transform3D).origin
		if o.is_finite() and o.z <= SUBURB_Z_MAX:
			out.append(o - Vector3(0.0, HEAD_DROP, 0.0))
	return out


## Per-light turn-on point inside the dusk ramp, hashed from the position so it
## is stable across runs and costs no RNG stream. A subdivision switching on
## house by house over the last minutes of dusk is the read; everything coming
## up at once is a light switch on a stage.
func _stagger(p: Vector3) -> float:
	var h := sin(p.x * 12.9898 + p.z * 78.233) * 43758.5453
	return (1.0 - STAGGER) + STAGGER * (h - floorf(h))


func _light(pos: Vector3, col: Color, energy: float, radius: float, att: float,
		fade: Vector2) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.light_specular = SPECULAR
	l.omni_range = radius
	l.omni_attenuation = att
	l.shadow_enabled = false                 # the whole budget rests on this
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade.x
	l.distance_fade_length = fade.y
	l.distance_fade_shadow = fade.x
	l.visible = false
	_root.add_child(l)
	return l


# ============================== PER FRAME ====================================
func _process(_delta: float) -> void:
	_frame += 1
	if _perf:
		_perf_tick(_delta)
	if _sky == null or not is_instance_valid(_sky):
		_sky = _find_sky()
		if _sky == null:
			return
	var tv: Variant = _sky.get("time_of_day")
	if not (tv is float):
		return
	var level := GLOW.level_for_hour(tv as float)
	if absf(level - _cur) > 0.0005:
		_apply(level)
		_cur = level
	if not _tv.is_empty() and level > 0.01 and _frame % TV_EVERY == 0:
		_flicker((tv as float) * 3600.0, level)


## Walk the sorted array from the current index. Only the lights whose
## threshold the level just crossed are touched — amortised O(1) across the
## whole ramp, and one full pass if the clock teleports.
func _apply(level: float) -> void:
	while _on < _ramp.size() and _thresh[_on] <= level:
		_ramp[_on].visible = true
		_on += 1
	while _on > 0 and _thresh[_on - 1] > level:
		_on -= 1
		_ramp[_on].visible = false
	for l in _tv:
		l.visible = level > 0.01
	if _dress != null and is_instance_valid(_dress) \
			and _dress.has_method("set_night_level"):
		_dress.call("set_night_level", level)    # two material writes, O(1)


## Pure function of the game clock: no accumulated state, so the --shot
## harness reproduces a frame after teleporting the clock. Two incommensurate
## sines beat against each other, which is what a cut between TV shots does.
func _flicker(game_s: float, level: float) -> void:
	for i in _tv.size():
		var ph := _tv_phase[i]
		var a := sin(game_s * TV_RATE + ph)
		var b := sin(game_s * TV_RATE * 2.37 + ph * 1.7)
		_tv[i].light_energy = TV_E * level * (1.0 + TV_SWING * a * b)


func _find_sky() -> Node:
	if main_ref == null:
		return null
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary):
		return null
	var s: Variant = (sys as Dictionary).get("sky_weather")
	if s is Node and is_instance_valid(s):
		return s as Node
	return null


# ============================ PERF HARNESS ===================================
## `godot -- --suburb-perf`. Parks a free camera at the exact suburb_night
## vantage, pins the clock to 21:48, and reports frame time percentiles over
## PERF_FRAMES so the district has a number, not an opinion. Never runs
## unless asked, so no gate and no normal session pays for it.
func _perf_tick(delta: float) -> void:
	if _perf_cam == null:
		if _frame < 30:
			return
		# A vsynced frame time is the MONITOR's number, not the renderer's, and
		# on this box vsync survives window_set_vsync_mode. So measure the
		# viewport directly: viewport_get_measured_render_time_gpu is the
		# renderer's own timestamp-query result and a display cap cannot
		# flatter it. That is also the number lighting actually moves.
		RenderingServer.viewport_set_measure_render_time(
			get_viewport().get_viewport_rid(), true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		for n in (main_ref as Node).get_children():
			if n is CanvasLayer:
				(n as CanvasLayer).visible = false
		_perf_cam = Camera3D.new()
		_perf_cam.far = 4000.0
		add_child(_perf_cam)
		_perf_cam.global_position = PERF_POS
		_perf_cam.look_at(PERF_LOOK, Vector3.UP)
		_perf_cam.make_current()
	var sky := _find_sky()
	if sky != null:
		sky.set("time_of_day", PERF_HOUR)
	_perf_n += 1
	if _perf_n <= PERF_WARMUP:
		return
	var vp := get_viewport().get_viewport_rid()
	_perf_ms.append(delta * 1000.0)
	_perf_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp)
		+ RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if _perf_ms.size() < PERF_FRAMES:
		return
	var v := Array(_perf_ms)
	v.sort()
	var c := Array(_perf_cpu)
	c.sort()
	var n := v.size()
	print(("SUBURB PERF @ suburb_night vantage, %d frames: frame median %.2f ms "
		+ "(%.0f fps), p95 %.2f ms, worst %.2f ms | renderer median "
		+ "%.2f ms | %d draw calls, %d objects | %d lights built, %d switched on")
		% [n, v[n / 2], 1000.0 / maxf(v[n / 2], 0.001),
			v[int(n * 0.95)], v[n - 1], c[n / 2],
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			_ramp.size() + _tv.size(), _on])
	get_tree().quit(0)
