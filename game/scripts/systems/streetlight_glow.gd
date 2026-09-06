extends Node
## STREETLIGHT GLOW (M14) — warm pools of light under the cobra heads at night.
## One MultiMesh of soft radial-gradient discs (PlaneMesh + smoothstep-alpha
## texture, no hard rim) floated at y 0.075: above the entire street paint
## stack (tops out 0.065) and under the 0.2 block slabs, so the curb clips the
## pool exactly where a curb would. The material is UNSHADED, NON-EMISSIVE,
## peak alpha POOL_ALPHA — nothing here can cross the 1.05 HDR bloom
## threshold, so pools glow warm on the asphalt and never flare flat white.
##
## Night logic: pool level is a pure function of sky_weather's game clock
## (full from just after sunset 19.5 to just before sunrise 7.5, with dusk and
## dawn ramps), NOT of wall time — so a teleported clock (the --shot harness,
## a future sleep mechanic) lands on the correct level within one frame.
## Budget: the sky peer is discovered/revalidated on a ~1 s poll; per frame we
## only read one cached float and touch the material when the level actually
## moves (the ~25 s dusk and dawn windows). Zero per-frame allocation.
## VISUAL-ONLY: no collision, no RNG at all.
##
## ===================== TWO POOL SETS (D-014, cycle 1) ========================
## ARTERIAL — one disc per cobra head published by a dressing peer through
##   get_streetlight_head_xfs(). Sized for a downtown arterial seen from a
##   3.5 m driving eye.
## SOFT — discs published by ANY dressing peer through get_light_pool_xfs(),
##   transform and all. The suburb uses these for its porch aprons and
##   driveway pads: half the alpha, a fifth of the area, and NOT under a
##   luminaire. They exist because the suburb's real OmniLights distance-fade
##   at ~130 m (see suburb_night.gd) — past that the decals are the whole read,
##   and a subdivision vista that goes black at 130 m is the defect we are
##   fixing. Near field: real light. Far field: two draw calls.
## INSTITUTIONAL — discs published through get_inst_pool_xfs() (D-069, cycle 2).
##   County General's apron, canopy, driveway and ER door. COLDER and roughly
##   twice the alpha of SOFT, because the thing casting them is a 4.5-energy
##   area luminaire on an 8.4 m mast, not somebody's porch bulb. They sit in
##   their own height stratum ABOVE the arterial set so they tint the apron's
##   painted stalls instead of z-fighting with them (the hospital's paint tops
##   out at 0.075 — greybox_city.gd:655 — where downtown's tops out at 0.065).
## The pool system no longer knows what a streetlight is; it takes transforms
## from whoever has them, which is why neither the suburb nor the hospital
## needed a line of new pool code — only a getter and a colour.

const TEX := preload("res://scripts/world/city_textures.gd")

const POOL_COLOR := Color(1.0, 0.80, 0.48)   # sodium-warm
const POOL_ALPHA := 0.28                     # peak — translucent, never a flare
const SOFT_COLOR := Color(1.0, 0.76, 0.42)   # incandescent, a touch warmer
const SOFT_ALPHA := 0.15                     # a porch is not a luminaire
const INST_COLOR := Color(0.80, 0.88, 1.0)   # 4000 K area lighting, cold
# 0.14, NOT the 0.30 I first reached for. A pool decal is UNSHADED: it pays no
# attention to distance, angle or anything else, so a big one seen from a 1.9 m
# eye standing inside it paints a flat slab across the bottom of the frame at
# exactly its own alpha. At 0.30 the hospital apron measured mean 51.7 and the
# near field was pure decal — the real lights were doing almost none of the
# work and the falloff I had just spent a build tuning was invisible under it.
# The decal's job here is a sheen under the head, not the lighting.
const INST_ALPHA := 0.14
const POOL_Y := 0.075                        # paint stack <= 0.065; slabs 0.2
const SOFT_Y := 0.071                        # under the arterial set, always
const INST_Y := 0.082                        # OVER the hospital apron's paint
                                             # (tops 0.075) and under the slabs
const ALONG_R := 8.6                         # half-axis down the street (m) —
const ACROSS_R := 5.4                        # sized for the 3.5 m driving eye:
                                             # at grazing angles smaller pools
                                             # compressed to invisible slivers
const AHEAD := 1.2                           # pool centre shifted past the head
# --- D-070: the 42 intersection pools that lay on a 45 degree diagonal.
# city_dressing.gd:1076 hangs the NW combination signal/luminaire mast on
# `into = (0.7071, 0, 0.7071)` — the arm reaches DIAGONALLY over the corner,
# which is a perfectly good mast and not a defect. The defect is downstream, in
# this file: the pool ellipse is oriented from the head's own `toward`, so a
# lane-shaped 8.6 x 5.4 m ellipse ended up lying across the intersection at 45
# degrees, 42 times. FIXED HERE, not there, because that is where it belongs —
# `city_dressing` owns where the steel goes and this system owns what the
# ground looks like under it, and no other owner's geometry, draw order or RNG
# is touched by the change (the MultiMesh keeps the same instance count and the
# same order; 42 of 536 transforms change shape).
# A luminaire hung over the middle of an intersection is not lighting a lane,
# it is washing a box. So a head whose `toward` is more than ~15 degrees off a
# cardinal axis gets a ROUND pool at zero yaw: no diagonal to be wrong about,
# deterministic, and a better description of what that fixture actually does.
const DIAG_TOL := 0.26                       # sin(15 deg); above this = diagonal
const BOX_R := 7.4                           # round intersection wash half-axis
const PEER_POLL_S := 1.0                     # sky/dressing discovery cadence
# Clock windows (h). sky_weather sun model: noon 13.5, sunset 19.5, rise 7.5.
const DUSK0 := 19.2
const DUSK1 := 20.1
const DAWN0 := 7.0
const DAWN1 := 7.9

var main_ref: Node = null
var _sky: Node = null
var _mmi: MultiMeshInstance3D = null
var _mat: StandardMaterial3D = null
var _mmi_soft: MultiMeshInstance3D = null
var _mat_soft: StandardMaterial3D = null
var _mmi_inst: MultiMeshInstance3D = null
var _mat_inst: StandardMaterial3D = null
var _built := false
var _soft_on := true
var _inst_on := true
var _poll_t := PEER_POLL_S
var _cur := -1.0                             # last applied level (force first set)
var _diag := 0                               # D-070: heads re-shaped to a box wash


## THE canonical night ramp, 0 (day) .. 1 (night), from the game clock.
## Static and pure so suburb_night.gd can share it instead of keeping a second
## copy of these four constants that would eventually disagree with this one.
## Teleport-safe by construction: no state, no wall time.
static func level_for_hour(t: float) -> float:
	if t >= DUSK1 or t < DAWN0:
		return 1.0
	if t >= DUSK0:                           # dusk: fade in
		return (t - DUSK0) / (DUSK1 - DUSK0)
	if t >= DAWN0 and t < DAWN1:             # dawn: fade out
		return 1.0 - (t - DAWN0) / (DAWN1 - DAWN0)
	return 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--no-light-pools"):         # toggle: kill both sets outright
		set_physics_process(false)
		set_process(false)
		return
	_soft_on = not args.has("--no-suburb-lights")
	_inst_on = not args.has("--no-hospital-lights")
	set_physics_process(false)
	_build_pools()


func _process(delta: float) -> void:
	_poll_t += delta
	if _poll_t >= PEER_POLL_S:               # ~1 Hz: peer discovery only
		_poll_t = 0.0
		if _sky == null or not is_instance_valid(_sky):
			_sky = _find_sky()
		if not _built:
			_build_pools()
	if _mat == null and _mat_soft == null and _mat_inst == null:
		return
	var level := _night_factor()
	if absf(level - _cur) > 0.003:           # touch the material only on change
		_cur = level
		if _mat != null:
			var c := POOL_COLOR
			c.a = POOL_ALPHA * level
			_mat.albedo_color = c
			_mmi.visible = level > 0.01      # by day the pools cost nothing
		if _mat_soft != null:
			var cs := SOFT_COLOR
			cs.a = SOFT_ALPHA * level
			_mat_soft.albedo_color = cs
			_mmi_soft.visible = level > 0.01
		if _mat_inst != null:
			var ci := INST_COLOR
			ci.a = INST_ALPHA * level
			_mat_inst.albedo_color = ci
			_mmi_inst.visible = level > 0.01


func _night_factor() -> float:
	if _sky == null or not is_instance_valid(_sky):
		return 0.0
	var tv: Variant = _sky.get("time_of_day")
	if not (tv is float):
		return 0.0
	return level_for_hour(tv as float)


func _find_sky() -> Node:
	if main_ref == null:
		return null
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary):
		return null
	var sky: Variant = (sys as Dictionary).get("sky_weather")
	if sky is Node and is_instance_valid(sky):
		return sky as Node
	return null


## Gather from every source, then build at most one MultiMesh per set. Returns
## quietly (and retries on the next poll) until the city exists.
func _build_pools() -> void:
	if _built or main_ref == null:
		return
	var city: Variant = main_ref.get("city")
	if not (city is Node3D) or not is_instance_valid(city):
		return
	var host := city as Node3D
	var arterial := _arterial_pools(host)
	var soft: Array[Transform3D] = []
	if _soft_on:
		soft = _soft_pools(host)
	var inst: Array[Transform3D] = []
	if _inst_on:
		inst = _peer_pools(host, "get_inst_pool_xfs", INST_Y)
	if arterial.is_empty() and soft.is_empty() and inst.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)           # unit half-extents; scaled per pool
	if not arterial.is_empty():
		_mat = _pool_mat(POOL_COLOR, 2)
		_mmi = _pool_mmi(plane, arterial, _mat, "StreetlightPools", host)
	if not soft.is_empty():
		_mat_soft = _pool_mat(SOFT_COLOR, 1)
		_mmi_soft = _pool_mmi(plane, soft, _mat_soft, "SoftLightPools", host)
	if not inst.is_empty():
		# Priority 3: over the arterial set. Nothing else draws in this stratum,
		# but if a future district ever overlaps the campus the institutional
		# pool is the one that should win — it is the brighter source.
		_mat_inst = _pool_mat(INST_COLOR, 3)
		_mmi_inst = _pool_mmi(plane, inst, _mat_inst, "InstitutionalPools", host)
	_built = true
	_cur = -1.0                              # force a level apply next frame
	print(("POOLS: arterial=%d (%d intersection box washes, D-070) soft=%d "
		+ "inst=%d (%d draw calls, 0 lights, 0 per-frame work)")
		% [arterial.size(), _diag, soft.size(), inst.size(),
			int(_mmi != null) + int(_mmi_soft != null) + int(_mmi_inst != null)])


## One disc per recorded cobra head, oriented so the ellipse runs down the
## street. Head record basis is looking_at(toward): toward = -basis.z.
func _arterial_pools(host: Node3D) -> Array[Transform3D]:
	var xfs: Array[Transform3D] = []
	var dressing := host.get_node_or_null("CityDressing")
	if dressing == null or not dressing.has_method("get_streetlight_head_xfs"):
		return xfs
	var heads_v: Variant = dressing.call("get_streetlight_head_xfs")
	if not (heads_v is Array):
		return xfs
	for v: Variant in (heads_v as Array):
		if not (v is Transform3D):
			continue
		var hx := v as Transform3D
		var toward := (-hx.basis.z).normalized()
		if not toward.is_finite() or toward.length_squared() < 0.5:
			continue
		var rot := Basis(Vector3.UP, atan2(toward.x, toward.z))  # +Z -> toward
		var half := Vector3(ALONG_R, 1.0, ACROSS_R)
		if minf(absf(toward.x), absf(toward.z)) > DIAG_TOL:   # D-070
			rot = Basis.IDENTITY
			half = Vector3(BOX_R, 1.0, BOX_R)
			_diag += 1
		var pos := Vector3(hx.origin.x, POOL_Y, hx.origin.z) + toward * AHEAD
		xfs.append(Transform3D(rot * Basis.from_scale(half), pos))
	return xfs


func _soft_pools(host: Node3D) -> Array[Transform3D]:
	return _peer_pools(host, "get_light_pool_xfs", SOFT_Y)


## Pools supplied whole by a peer. The peer owns the size, shape and rotation
## (it knows which way its wall faces); this system owns only the height
## stratum, so Y is overwritten and nothing else is touched.
##
## TWO PLACES ARE SCANNED, and both are needed. A *dressing* layer is a child of
## the city and publishes at city-build time (the suburb). A *runtime light
## system* is a child of main, in `systems`, and publishes during its own setup
## (the hospital). Scanning only the city's children silently dropped the
## institutional set and cost me one build to find; scanning both makes the
## contract "whoever has transforms", which is what the header claims.
func _peer_pools(host: Node3D, method: String, y: float) -> Array[Transform3D]:
	var xfs: Array[Transform3D] = []
	var peers: Array = host.get_children()
	var sysv: Variant = main_ref.get("systems") if main_ref != null else null
	if sysv is Dictionary:
		peers = peers + (sysv as Dictionary).values()
	for peer: Variant in peers:
		if not (peer is Node) or not (peer as Node).has_method(method):
			continue
		var got: Variant = (peer as Node).call(method)
		if not (got is Array):
			continue
		for v: Variant in (got as Array):
			if not (v is Transform3D):
				continue
			var t := v as Transform3D
			if not t.origin.is_finite():
				continue
			xfs.append(Transform3D(t.basis, Vector3(t.origin.x, y, t.origin.z)))
	return xfs


func _pool_mat(col: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = TEX.light_pool_texture()
	var c0 := col
	c0.a = 0.0
	m.albedo_color = c0
	m.render_priority = priority             # over the tire-wear translucency
	return m


func _pool_mmi(mesh: Mesh, xfs: Array[Transform3D], m: StandardMaterial3D,
		label: String, host: Node3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	host.add_child(mmi)
	return mmi
