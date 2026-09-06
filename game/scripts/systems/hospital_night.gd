extends Node
## COUNTY GENERAL NIGHT LIGHTING (D-069) — the institutional light rig for the
## hospital campus, and the reason the post-death frame is not a black hole.
##
## THE DEFECT, AND WHERE IT CAME FROM. Fixing the suburb (D-014, 2.52 -> 9.87)
## did not make the hospital darker; it made it FIRST. QA measured the ground
## half of `hospital_night` at mean 4.23/255 with 92.3 % of pixels under 8/255 —
## the worst night read in the game, and the only one that is MANDATORY: County
## General is the respawn (`on_foot.gd:216`), so every player sees this frame,
## at night, after every single death. A dark void is the worst possible first
## frame after a death card.
##
## THE READ WE ARE AFTER. A county hospital at 2 a.m. is the one thing on a
## dark prairie that somebody pays to keep lit all night, and it is lit by an
## institution, not by householders. So it is BRIGHTER and COLDER than the
## suburb and much less busy than downtown:
##   the ER porte-cochere blazing        -> 4 cool omnis under the canopy deck
##   sodium/LED over the ambulance apron -> 6 shoebox masts on 8.4 m poles
##   the same over the approach drive    -> 2 more on the driveway
##   the ER doors you walk out of        -> 1 warm omni outside the glass
##   the ward slab washed from its base  -> 3 uplights on the north face
##   pooling on the asphalt              -> 12 institutional decals (1 draw call)
## Warm/cold is the whole art direction here: the ward's own windows are warm
## (greybox_city's `tower_material`, 28 % of panes lit) and everything the
## county pays for is cold. That contrast is what makes it read as a hospital
## rather than as a lit building.
##
## WHAT WAS ALREADY THERE AND IS LEFT ALONE: the red EMERGENCY fascia
## (`greybox_city.gd:643-651`, emission 1.6), the helipad's four corner lights
## (`:618-627`, emission 1.8) and the lit ward panes. They were the *only*
## things reading in the defect screenshot. They still read; they now have a
## place to read against.
##
## ============================= THE BUDGET ====================================
##  * 16 OmniLight3D, NO shadows, ever. Not one shadow map. (The suburb needed
##    492 to cover 91 hectares of plat; a campus is 52 x 46 m and needs 16.)
##  * Every light distance-fades and is CULLED at begin+length, so the cost is
##    how many are in frustum, not how many exist. Live from the downtown
##    approach (222 m), dead from the freeway.
##  * Per frame: ONE float compare. Level changes touch 16 lights and 3
##    materials — O(1) in campus size and it only happens during the ~25 s dusk
##    and dawn ramps.
##  * Geometry is 3 MultiMeshes (poles+arms, housings, lenses) = 3 draw calls
##    for 8 complete luminaires. Pools ride streetlight_glow's institutional set
##    for 1 more.
##  * Nothing here animates, so every screenshot regression test reproduces.
##
## TOGGLES (working convention: every visual feature ships with one)
##   --no-hospital-lights   build nothing; the district reverts to the D-069 read
## and a profiler line is printed at build in every run.
##
## OWNERSHIP: creates OmniLight3D and MultiMeshInstance3D nodes under one
## container parented to the city. Touches no existing geometry, no collision,
## no RNG stream, no material anybody else owns, and nothing in smoke mode.
##
## GEOMETRY CONTRACT. Every position here is an offset from the ER door, which
## the city publishes as `get_hospital_spawn()`. That is deliberate: the campus
## literals live in `greybox_city.gd:590-668` (someone else's file) and hard
## copies of them here would be a drift bomb. Anchor on the one coordinate that
## is a published contract and the rig follows the hospital if it ever moves.

const GLOW := preload("res://scripts/systems/streetlight_glow.gd")

# --- Colour. Cold on purpose: 4000 K-ish LED area lighting against the ward's
# warm 2700 K window glow. `INST` is every county-paid fixture; `DOOR` is the
# one warm lamp, over the door the player walks out of, so the exit reads as an
# entrance and not as a loading dock.
const INST_COL := Color(0.84, 0.90, 1.0)
const DOOR_COL := Color(1.0, 0.86, 0.62)
const LENS_COL := Color(0.88, 0.94, 1.0)     # the emissive lens plate
const LENS_E := 1.5                          # over the 1.05 HDR gate: a lens
                                             # SHOULD bloom; the housing must not

# --- Apron / driveway masts. THE FALLOFF IS THE POINT, and the first build got
# this exactly wrong: 6 heads at energy 4.5 / range 30 / 1-over-d measured the
# ground half at mean 67.2 with 43 % of it over 64/255 — an even, shadowless
# grey lot that read as an overcast afternoon with a night sky pasted behind
# it. A lot at 2 a.m. is not uniformly lit; it is a row of POOLS with dark
# between them, and the dark is what makes the pools read.
# So: shorter range, steeper falloff, lower energy. At attenuation 1.45,
# 0.18 asphalt gives 0.18 * 8.05^-1.45 * E directly under the head and about a
# third of that 10 m out — a real gradient instead of a wash.
const MAST_E := 2.0
const MAST_R := 24.0
const MAST_ATT := 1.45                       # steep: pools, not floodlight
const MAST_H := 8.4                          # pole height (m)
const MAST_LIGHT_Y := 8.05                   # omni, on the arm tip
const MAST_ARM := 1.6                        # arm reach toward the lot (m)
# A 3-cm float, found by cropping the day shot at 3x. The campus does not sit
# on one plane: greybox_city's apron slab tops out at y +0.02 and the prairie
# it stands on tops out at -0.02/-0.03 (`_slab(rect, top, ...)`, :168-174), so
# the two driveway masts — the only ones not on pavement — hovered above their
# own shadow. Poles are sunk below the LOWEST of those surfaces instead of
# being placed on the highest. Nobody sees a buried 25 cm; everybody sees a
# floating 3 cm, and the bar's "no floating geometry" row is checked at every
# vantage, not at the flattering ones.
const MAST_SINK := 0.25
const MAST_POOL := Vector2(7.5, 7.5)         # round: a lot pool is not a lane

# --- ER canopy. Sits 1.3 m under a 0.47-albedo concrete soffit, so the energy
# is capped by THAT, not by the ground: 0.47 * 1.3^-1.35 * E must stay under
# main.gd's 1.05 glow_hdr_threshold or the whole porte-cochere hazes white.
# E = 1.5 lands at 0.50 direct and ~0.6 where two fixtures overlap: a bright
# ceiling that is still a ceiling. The ground 3.3 m below stays the brightest
# asphalt on the campus, which is correct — it is the bit with an ambulance in
# it and the bit you walk out into.
const CANOPY_E := 1.5
const CANOPY_R := 20.0
const CANOPY_ATT := 1.35
const CANOPY_Y := 3.3
const CANOPY_POOL := Vector2(7.4, 4.6)       # the deck footprint, plus spill

# --- ER door lamp: warm, small, right outside the glass.
const DOOR_E := 1.5
const DOOR_R := 12.0
const DOOR_ATT := 1.1
const DOOR_POOL := Vector2(4.2, 3.4)

# --- Ward wall-wash. Stood 1.2 m off the face so the hot spot at the base
# stays under the bloom gate. Kept LOW on purpose: the ward's own warm window
# panes are the read up there, and the first build's 2.0 lit the whole curtain
# wall to a flat pale grey that swallowed them. A wall-wash should die out
# around the second floor and leave the tower to its windows.
const WASH_E := 1.0
const WASH_R := 12.0
const WASH_ATT := 1.1
const WASH_Y := 1.2
const WASH_OFF := 1.2                        # distance off the ward face

# --- Distance fade (begin, length); culled at begin+length. Chosen against the
# real vantages: the hospital is 222 m from the downtown street vantage (lights
# live, you can see the campus glow as you drive down) and ~700 m from the
# freeway/skyline vantages (culled — at that range the emissive fascia, the lens
# plates and the pool decals are the whole read). A deliberate lighting LOD.
const FADE := Vector2(260.0, 120.0)
const SPECULAR := 0.35                       # matches suburb_night: full
                                             # specular puts hard dots on glass

# --- Campus geometry, as offsets from the ER door (see the GEOMETRY CONTRACT
# note above). Source of truth for the shapes these serve: greybox_city.gd
# :596 apron 52 x 26 centred (x, z-6.5) | :639 canopy 14 x 0.5 x 8 at
# (x, 4.85, z-3.5) | :599 ward 42 x 18 x 15 at (x, 9.1, z+19) | :596 driveway
# 12 x 26 at (x, z-31.5).
## Six heads, not eight. Real 8.4 m shoeboxes go up on a 25-30 m spacing; the
## first build put six of them on a 52 x 26 m apron, which is a spacing of 13 m
## and is why the lot came out uniform. Four on the apron corners and two down
## the driveway leaves genuine dark between the pools.
const MASTS: Array[Vector2] = [              # (dx, dz) of each pole base
	Vector2(-20.0, -13.0), Vector2(20.0, -13.0),      # apron, north row
	Vector2(-20.0, 3.0), Vector2(20.0, 3.0),          # apron, south row
	Vector2(-8.5, -22.0), Vector2(-8.5, -36.0),       # the approach driveway
]
const CANOPY_LIGHTS: Array[Vector2] = [
	Vector2(-3.4, -5.5), Vector2(3.4, -5.5),
	Vector2(-3.4, -1.5), Vector2(3.4, -1.5),
]
const WASH_DX: Array[float] = [-14.0, 0.0, 14.0]
const WARD_FACE_DZ := 11.5                   # ward's north face, from the door
const DOOR_DZ := 0.9                         # lamp stands proud of the glass

var main_ref: Node = null
var _sky: Node = null
var _root: Node3D = null
var _pools: Array[Transform3D] = []          # published to streetlight_glow
var _lights: Array[OmniLight3D] = []
var _base_e := PackedFloat32Array()          # each light's full-night energy
var _lens_mats: Array[StandardMaterial3D] = []
var _cur := -1.0
var _counts := Vector4i.ZERO                 # mast, canopy, wash, door


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_process(false)
		return
	if OS.get_cmdline_user_args().has("--no-hospital-lights"):
		print("HOSPITAL NIGHT: disabled (--no-hospital-lights)")
		set_process(false)
		return
	_build()


# ============================== BUILD ========================================
func _build() -> void:
	var city: Variant = main_ref.get("city")
	if not (city is Node3D) or not is_instance_valid(city):
		set_process(false)
		return
	var host := city as Node3D
	if not host.has_method("get_hospital_spawn"):
		# A city build without the hospital contract has no campus to light.
		set_process(false)
		return
	var got: Variant = host.call("get_hospital_spawn")
	if not (got is Transform3D):
		set_process(false)
		return
	var d: Vector3 = (got as Transform3D).origin
	d.y = 0.0                                # work off the pavement, not the feet
	if not d.is_finite():
		set_process(false)
		return
	var t0 := Time.get_ticks_usec()
	_root = Node3D.new()
	_root.name = "HospitalNightLights"
	host.add_child(_root)

	# --- Masts: pole, arm, housing, lens, light, pool. The arm reaches toward
	# the campus centreline so every head hangs over pavement, not over grass.
	var poles: Array[Transform3D] = []
	var housings: Array[Transform3D] = []
	var lenses: Array[Transform3D] = []
	for m in MASTS:
		var base := d + Vector3(m.x, 0.0, m.y)
		var reach := Vector3(-signf(m.x) if absf(m.x) > 0.01 else 0.0, 0.0, 0.0)
		if reach.length_squared() < 0.5:
			reach = Vector3(0, 0, -1)
		var tip := base + reach * MAST_ARM
		poles.append(Transform3D(
			Basis.from_scale(Vector3(0.22, MAST_H + MAST_SINK, 0.22)),
			base + Vector3(0, (MAST_H - MAST_SINK) * 0.5, 0)))
		poles.append(Transform3D(Basis.from_scale(
			Vector3(maxf(absf(reach.x) * MAST_ARM, 0.16),
				0.16, maxf(absf(reach.z) * MAST_ARM, 0.16))),
			base + reach * (MAST_ARM * 0.5) + Vector3(0, MAST_H - 0.05, 0)))
		housings.append(Transform3D(Basis.from_scale(Vector3(0.85, 0.14, 0.5)),
			tip + Vector3(0, MAST_H - 0.12, 0)))
		lenses.append(Transform3D(Basis.from_scale(Vector3(0.72, 0.02, 0.4)),
			tip + Vector3(0, MAST_H - 0.20, 0)))
		_add(tip + Vector3(0, MAST_LIGHT_Y, 0), INST_COL, MAST_E, MAST_R, MAST_ATT)
		_pool(tip, MAST_POOL)
	_counts.x = MASTS.size()

	# --- ER canopy: the bright box. No fixture geometry — these hang inside a
	# 0.5 m concrete deck that is already modelled, and a soffit fixture at this
	# scale would be four more draw calls to render four dots nobody can see.
	for c in CANOPY_LIGHTS:
		_add(d + Vector3(c.x, CANOPY_Y, c.y), INST_COL, CANOPY_E, CANOPY_R,
			CANOPY_ATT)
	_counts.y = CANOPY_LIGHTS.size()
	_pool(d + Vector3(0.0, 0.0, -3.5), CANOPY_POOL)

	# --- Ward wall-wash: the north face is the biggest black mass in the frame.
	for dx in WASH_DX:
		_add(d + Vector3(dx, WASH_Y, WARD_FACE_DZ - WASH_OFF), INST_COL, WASH_E,
			WASH_R, WASH_ATT)
	_counts.z = WASH_DX.size()

	# --- The door you wake up at.
	_add(d + Vector3(0.0, 2.4, DOOR_DZ), DOOR_COL, DOOR_E, DOOR_R, DOOR_ATT)
	_counts.w = 1
	_pool(d + Vector3(0.0, 0.0, DOOR_DZ - 1.6), DOOR_POOL)

	_mm(poles, _mat(Color(0.22, 0.23, 0.25), false, 0.0), "HospitalMasts")
	# The housing sits 0.23 m under a 4.5-energy source. Any SHADED material
	# there reads 0.22 * 0.23^-1.0 * 4.5 = 4.3 — four times the bloom gate, and
	# the whole fixture would haze into a white blob. UNSHADED is not a cheat
	# here, it is the only way a dark shoebox stays a dark shoebox directly
	# under its own lamp.
	_mm(housings, _mat(Color(0.16, 0.17, 0.18), true, 0.0), "HospitalLuminaires")
	var lens_mat := _mat(LENS_COL, true, LENS_E)
	_lens_mats.append(lens_mat)
	_mm(lenses, lens_mat, "HospitalLenses")

	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print(("HOSPITAL NIGHT: %d lights (mast %d, canopy %d, wash %d, door %d), "
		+ "%d pools, 0 shadow maps, 3 draw calls, built in %.1f ms")
		% [_lights.size(), _counts.x, _counts.y, _counts.z, _counts.w,
			_pools.size(), ms])
	if _lights.is_empty():
		set_process(false)


func _add(pos: Vector3, col: Color, energy: float, radius: float,
		att: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = 0.0                     # dark until the ramp says otherwise
	l.light_specular = SPECULAR
	l.omni_range = radius
	l.omni_attenuation = att
	l.shadow_enabled = false                 # the whole budget rests on this
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE.x
	l.distance_fade_length = FADE.y
	l.distance_fade_shadow = FADE.x
	l.visible = false
	_root.add_child(l)
	_lights.append(l)
	_base_e.append(energy)


## A ground pool for streetlight_glow's institutional set. Half-extents in the
## basis, world position in the origin; the pool system overwrites Y (it owns
## the height stratum) and touches nothing else.
func _pool(centre: Vector3, half: Vector2) -> void:
	_pools.append(Transform3D(Basis.from_scale(Vector3(half.x, 1.0, half.y)),
		Vector3(centre.x, 0.0, centre.z)))


## CONTRACT for streetlight_glow.gd — the institutional pool set. Same shape as
## `get_light_pool_xfs`, deliberately a different name: these are colder and
## twice the alpha of the suburb's porch pads and must not land in that set.
func get_inst_pool_xfs() -> Array[Transform3D]:
	return _pools


func _mat(col: Color, unshaded: bool, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.8
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.0   # ramped; dark by day
	return m


func _mm(xfs: Array[Transform3D], m: StandardMaterial3D, label: String) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)


# ============================== PER FRAME ====================================
## One float compare. The campus is on a photocell, not on 245 householders, so
## there is no stagger and no sorted ramp to walk: everything crosses together,
## which is exactly what an institution looks like and is also the cheapest
## thing to implement. Energy is scaled by the level so dusk is a dimmer, not a
## switch, and the whole apply is O(lights) on CHANGE only — 16 writes during
## the ~25 s dusk window, zero for the rest of the day.
func _process(_delta: float) -> void:
	if _sky == null or not is_instance_valid(_sky):
		_sky = _find_sky()
		if _sky == null:
			return
	var tv: Variant = _sky.get("time_of_day")
	if not (tv is float):
		return
	var level := GLOW.level_for_hour(tv as float)
	if absf(level - _cur) <= 0.0005:
		return
	_cur = level
	var on := level > 0.005
	for i in _lights.size():
		_lights[i].visible = on
		if on:
			_lights[i].light_energy = _base_e[i] * level
	for m in _lens_mats:
		m.emission_energy_multiplier = LENS_E * level


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
