extends Node3D
## SUBURB DRESSING (M15) — the north fringe stops being bare brick boxes.
## Reads greybox_city's recorded house transforms/sizes (a frozen contract —
## zero seeded-RNG replay) and gives every house what a Texas subdivision
## actually has: a pitched shingle roof with eave overhang, a chimney, facade
## trim (door + windows + garage door, all PROUD of the wall — the hard-won
## project law: recessed quads are invisible), a concrete driveway and front
## walk with a worn dirt apron at the mouth, a mailbox, low wood fence runs,
## the odd shed and trampoline, and porch lights + ~35% warm-lit windows so
## the subdivision exists at night.
##
## CONTRACT: visual-only (zero collision, nothing physical), all randomness
## from a FRESH RNG with a literal seed (555001 — never the city's streams),
## every repeated element a MultiMesh, zero per-frame cost (no _process).
## LAW: rot * Basis.from_scale(v) always — never Basis.scaled() on a rotated
## box. MultiMesh instance colors clamped <= 1.0 (HDR tints read as glow).
##
## ============================ NIGHT (D-014) ==================================
## The suburb measured 2.52 mean luminance over the ground half of the frame
## with 100% of pixels under 8/255 — a mathematically black void — because the
## only things it emitted were a 22 cm porch fixture and ~35% lit panes. Emissive
## quads are SEEN; they do not LIGHT anything, so every wall, roof, driveway and
## yard stayed at zero. This file now also PUBLISHES, per house, where the real
## light sources belong:
##   * one warm porch light, 0.85 m proud of the front wall beside the door
##   * a cool driveway flood over the garage door on ~30% of houses
##   * blue TV spill outside ONE lit front window on ~14% of houses
##   * a soft ground pool under each of those, for the far read after the
##     lights themselves distance-fade out (see streetlight_glow.gd)
## `suburb_night.gd` turns those points into OmniLight3Ds; `streetlight_glow.gd`
## turns the pools into decals. Neither exists at build time and both are
## optional — this file draws exactly the same geometry with or without them.
##
## SEED DISCIPLINE: every draw the night pass makes comes from `_nrng`
## (NIGHT_SEED, its own literal), and the pass runs AFTER the house loop has
## finished. Not one draw is taken from `_rng`, so every house's shingle,
## door colour, fence, shed and lit-window coin flip is bit-identical to the
## build that shipped before this pass existed — the day read cannot move.

const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")

const SEED := 555001
const NIGHT_SEED := 555777           # night pass ONLY — never `_rng`
const EAVE := 1.0                    # roof footprint = house + 0.5 m each side
const RIDGE_W := 0.16                # ridge "point" width (true 0 makes slivers)

# Shingle palette — muted North Texas roofscape. Charcoal, brown, weathered
# red, sage. Applied as MultiMesh instance colors (clamped, never HDR).
# Kept DARK on purpose: the slopes are ~24 degrees off horizontal, so the
# 13:00 sun hits them nearly square — a 0.24 charcoal rendered at (206,190,168)
# in the round-1 shot (pixel-sampled, not eyeballed). These read as shingle
# in full sun and go properly dark at night.
const SHINGLES: Array[Color] = [
	Color(0.17, 0.165, 0.165), Color(0.26, 0.20, 0.15),
	Color(0.34, 0.19, 0.15), Color(0.24, 0.27, 0.20)]
# Front doors get one muted statement color each.
const DOOR_COLORS: Array[Color] = [
	Color(0.38, 0.16, 0.14), Color(0.16, 0.24, 0.32), Color(0.22, 0.30, 0.24),
	Color(0.30, 0.22, 0.16), Color(0.20, 0.20, 0.22)]
const SHED_COLORS: Array[Color] = [
	Color(0.46, 0.41, 0.34), Color(0.42, 0.25, 0.19), Color(0.36, 0.38, 0.33)]

# Night pass tunables. Sized against the frame budget, not against taste:
# every point below becomes ONE shadowless OmniLight3D that distance-fades, so
# the cost that matters is how many can be lit at once, not how many exist.
const FLOOD_CHANCE := 0.30           # houses with a driveway floodlight
const TV_CHANCE := 0.14              # of houses with a lit front window
const TV_CAP := 40                   # hard ceiling, whatever the house count
const PORCH_OUT := 0.85              # light stands this far proud of the wall
const PORCH_Y := 2.40
const FLOOD_OUT := 0.45              # flood is bracketed to the garage header
const FLOOD_Y := 3.15                # over the 2.2 m garage door, under the eave
const TV_OUT := 0.90                 # spill light just outside the pane
const TV_Y := 1.55                   # the lit-window centre height
# Ground pools (decals, drawn by streetlight_glow). Half-axes in metres:
# X runs ALONG the wall, Z runs OUT from it — the transform published here
# already carries that rotation, so the pool system never has to guess.
const PORCH_POOL := Vector2(2.9, 2.4)
const PORCH_POOL_OUT := 1.9
const DRIVE_POOL := Vector2(2.0, 3.9)
const DRIVE_POOL_OUT := 3.5          # the driveway pad centre
# Emissive energies, day -> night. The day values are the ones that shipped, so
# set_night_level(0) is a bit-identical no-op on the day vantages; the night
# values are the most these can carry before the fixture stops reading as a
# fixture and starts hazing the wall behind it.
const PORCH_DAY_E := 1.6; const PORCH_NIGHT_E := 3.4
const LIT_DAY_E := 1.0;   const LIT_NIGHT_E := 2.1

var _rng := RandomNumberGenerator.new()
var _nrng := RandomNumberGenerator.new()     # NIGHT PASS ONLY
var _unit := BoxMesh.new()
var _no_cols: Array[Color] = []      # typed empty for _mm calls without tints

# Accumulators — one MultiMesh per element type at flush.
var _roofs: Dictionary = {}          # size key -> {mesh, xf, col}
var _chimneys: Array[Transform3D] = []
var _trim: Array[Transform3D] = []           # white/cream frames, all openings
var _doors: Array[Transform3D] = []
var _door_cols: Array[Color] = []
var _garages: Array[Transform3D] = []
var _glass_dark: Array[Transform3D] = []
var _glass_lit: Array[Transform3D] = []
var _porch: Array[Transform3D] = []
var _concrete: Array[Transform3D] = []       # driveways + front walks
var _aprons: Array[Transform3D] = []         # worn dirt at the driveway mouth
var _wood: Array[Transform3D] = []           # fence posts/rails + mailbox posts
var _mail_heads: Array[Transform3D] = []
var _shed_bodies: Array[Transform3D] = []
var _shed_cols: Array[Color] = []
var _shed_roofs: Array[Transform3D] = []
var _tramp_discs: Array[Transform3D] = []
var _tramp_legs: Array[Transform3D] = []

# --- Night records. Filled by _house() with ZERO rng draws (they are pure
# functions of geometry already computed); winnowed by _night_pass() using
# _nrng only. Published, never rendered by this file.
var _porch_pts: Array[Vector3] = []          # one per house, in build order
var _porch_pools: Array[Transform3D] = []
var _flood_cand: Array[Vector3] = []         # parallel to _porch_pts
var _flood_pools: Array[Transform3D] = []
var _tv_cand: Array[Vector3] = []            # first LIT FRONT window per house
var _flood_pts: Array[Vector3] = []          # after the coin flips
var _tv_pts: Array[Vector3] = []
var _soft_pools: Array[Transform3D] = []     # porch + driveway pools, kept ones
var _house_i := -1                           # index of the house being built
var _porch_mat: StandardMaterial3D = null    # kept for set_night_level()
var _lit_mat: StandardMaterial3D = null


func build(city: Node3D) -> void:
	_rng.seed = SEED
	_unit.size = Vector3.ONE
	if not (city.has_method("get_house_xforms") and city.has_method("get_house_sizes")):
		return
	var got_x: Variant = city.call("get_house_xforms")
	var got_s: Variant = city.call("get_house_sizes")
	if not (got_x is Array and got_s is Array):
		return
	var xfs: Array = got_x as Array
	var szs: Array = got_s as Array
	for i in mini(xfs.size(), szs.size()):
		var vx: Variant = xfs[i]
		var vs: Variant = szs[i]
		if vx is Transform3D and vs is Vector3:
			_house_i += 1
			_house(vx as Transform3D, vs as Vector3)
	_night_pass()
	_flush()


# ============================== ONE HOUSE ====================================
## House local frame (box axis-aligned in local space): u_t runs along the
## LONG horizontal axis (the ridge), u_s across it. The "street-facing" long
## wall is picked per house — the suburb has no drawn roads yet, so the front
## is a fiction, but a consistent one: door, garage, driveway, walk, mailbox
## and apron all agree on it.
func _house(hxf: Transform3D, size: Vector3) -> void:
	var long_z := size.z >= size.x
	var u_t := Vector3(0, 0, 1) if long_z else Vector3(1, 0, 0)
	var u_s := Vector3(1, 0, 0) if long_z else Vector3(0, 0, 1)
	var wall_off := (size.x if long_z else size.z) * 0.5
	var hw := (size.z if long_z else size.x) * 0.5     # half long-wall width
	var top := hxf.origin.y + size.y * 0.5             # eave line
	var fs := 1.0 if _rng.randf() < 0.5 else -1.0      # which long wall is front
	var gs := 1.0 if _rng.randf() < 0.5 else -1.0      # which end holds the garage
	var rise := _roof(hxf, size, long_z, top)
	# Chimney on ~35%: a brick box straddling the ridge, top proud of it.
	if _rng.randf() < 0.35:
		var ct := (hw * 2.0 + EAVE) * 0.24 * (1.0 if _rng.randf() < 0.5 else -1.0)
		var clp := u_t * ct + u_s * 0.35
		_chimneys.append(Transform3D(hxf.basis * Basis.from_scale(Vector3(0.55, 2.2, 0.55)),
			_wp(hxf, clp.x, clp.z, top + rise - 0.8)))
	# --- Front facade -------------------------------------------------------
	var n_f := u_s * fs
	var rot_f := Basis(Vector3.UP, atan2(n_f.x, n_f.z))  # local +Z -> out the wall
	var g_t := gs * (hw - 1.9)                           # garage bay center
	var d_t := gs * (hw - 4.8) + _rng.randf_range(-0.2, 0.2)
	# Garage door (2.6 m) + trim at one end of the long face.
	_quad(_trim, hxf, rot_f, Vector3(3.0, 2.4, 0.10), n_f * (wall_off + 0.01) + u_t * g_t, 1.02)
	_quad(_garages, hxf, rot_f, Vector3(2.6, 2.2, 0.12), n_f * (wall_off + 0.035) + u_t * g_t, 1.0)
	# Front door + trim + porch light above.
	_quad(_trim, hxf, rot_f, Vector3(1.35, 2.35, 0.10), n_f * (wall_off + 0.01) + u_t * d_t, 1.12)
	_quad(_doors, hxf, rot_f, Vector3(1.0, 2.08, 0.12), n_f * (wall_off + 0.035) + u_t * d_t, 0.98)
	var dc: Color = DOOR_COLORS[_rng.randi_range(0, DOOR_COLORS.size() - 1)]
	_door_cols.append(_clamped(dc * _rng.randf_range(0.85, 1.05)))
	var p_t := d_t - gs * 0.95                         # porch fixture, along wall
	_quad(_porch, hxf, rot_f, Vector3(0.26, 0.34, 0.11),
		n_f * (wall_off + 0.03) + u_t * p_t, 2.35)
	# --- Night records: pure geometry, ZERO rng draws ------------------------
	var pl := n_f * (wall_off + PORCH_OUT) + u_t * p_t
	_porch_pts.append(_wp(hxf, pl.x, pl.z, PORCH_Y))
	_porch_pools.append(_pool(hxf, rot_f,
		n_f * (wall_off + PORCH_POOL_OUT) + u_t * p_t, PORCH_POOL))
	var fl := n_f * (wall_off + FLOOD_OUT) + u_t * g_t
	_flood_cand.append(_wp(hxf, fl.x, fl.z, FLOOD_Y))
	_flood_pools.append(_pool(hxf, rot_f,
		n_f * (wall_off + DRIVE_POOL_OUT) + u_t * g_t, DRIVE_POOL))
	_tv_cand.append(Vector3.INF)              # replaced by the first lit pane
	# Windows: 2-3 marching down the rest of the front wall.
	for k in _rng.randi_range(2, 3):
		var w_t := gs * (hw - 7.2 - 2.3 * float(k)) + _rng.randf_range(-0.15, 0.15)
		_window(hxf, rot_f, n_f, u_t, wall_off, w_t, true)
	# Back wall: two windows so the night read works from every side.
	var rot_b := Basis(Vector3.UP, atan2(-n_f.x, -n_f.z))
	for bt: float in [-hw * 0.35, hw * 0.35]:
		_window(hxf, rot_b, -n_f, u_t, wall_off, bt + _rng.randf_range(-0.3, 0.3), false)
	# --- Driveway, walk, apron, mailbox ------------------------------------
	_quad(_concrete, hxf, rot_f, Vector3(3.0, 0.04, 7.6), n_f * (wall_off + 3.5) + u_t * g_t, 0.02)
	_quad(_concrete, hxf, rot_f, Vector3(0.9, 0.04, 5.6), n_f * (wall_off + 2.5) + u_t * d_t, 0.022)
	_quad(_aprons, hxf, rot_f, Vector3(4.6, 0.03, 3.4), n_f * (wall_off + 8.6) + u_t * g_t, 0.008)
	var m_lp := n_f * (wall_off + 6.8) + u_t * (g_t - gs * 2.1)
	_wood.append(Transform3D(hxf.basis * Basis.from_scale(Vector3(0.09, 1.05, 0.09)),
		_wp(hxf, m_lp.x, m_lp.z, 0.5)))
	_mail_heads.append(Transform3D(hxf.basis * rot_f * Basis.from_scale(Vector3(0.30, 0.26, 0.52)),
		_wp(hxf, m_lp.x, m_lp.z, 1.15)))
	# --- Yard: fences, shed, trampoline -------------------------------------
	# Side-yard fences off the gable ends, running front-to-back.
	for side_i in 2:
		var ss := 1.0 if side_i == 0 else -1.0
		if _rng.randf() < (0.55 if side_i == 0 else 0.3):
			_fence_run(hxf, u_t * ss * (hw + 3.5), u_s, wall_off * 2.0 + 8.0)
	# Back-yard privacy line behind ~35%.
	if _rng.randf() < 0.35:
		_fence_run(hxf, -n_f * (wall_off + 5.5), u_t, hw * 2.0 + 4.0)
	if _rng.randf() < 0.25:
		_shed(hxf, -n_f * (wall_off + 3.6) + u_t * _rng.randf_range(-3.0, 3.0))
	if _rng.randf() < 0.08:
		_trampoline(hxf, u_t, u_s,
			-n_f * (wall_off + _rng.randf_range(5.0, 8.0)) + u_t * _rng.randf_range(-4.0, 4.0))


# ============================== ROOF =========================================
## Gable roof from mesh_kit.taper: a box whose top face pinches to a thin
## strip along the LONG local axis — sloped sides, vertical triangular gable
## ends, eave overhang all around, seated on the eave line. One ArrayMesh per
## house variant (taper caches by parameter key), grouped into one MultiMesh
## per variant with per-instance shingle colors. Returns the rise.
func _roof(hxf: Transform3D, size: Vector3, long_z: bool, top: float) -> float:
	var fx := size.x + EAVE
	var fz := size.z + EAVE
	var rise := clampf((fx if long_z else fz) * 0.22, 2.2, 2.8)
	var key := "%.2f_%.2f_%d" % [size.x, size.z, int(long_z)]
	if not _roofs.has(key):
		var top_sz := Vector2(RIDGE_W, fz) if long_z else Vector2(fx, RIDGE_W)
		_roofs[key] = {
			"mesh": MESH_KIT.taper(Vector3(fx, rise, fz), top_sz),
			"xf": [] as Array[Transform3D],
			"col": [] as Array[Color],
		}
	var g: Dictionary = _roofs[key]
	(g["xf"] as Array[Transform3D]).append(Transform3D(hxf.basis,
		Vector3(hxf.origin.x, top + rise * 0.5, hxf.origin.z)))
	var c: Color = SHINGLES[_rng.randi_range(0, SHINGLES.size() - 1)]
	(g["col"] as Array[Color]).append(_clamped(c * _rng.randf_range(0.85, 1.08)))
	return rise


# ============================== PIECES =======================================
## One window: cream trim frame, then the glass pane proud of the trim.
## ~35% draw the lit material — emission peaks under the 1.05 bloom threshold,
## so night windows read warm, never haze.
func _window(hxf: Transform3D, rot: Basis, n: Vector3, u_t: Vector3,
		wall_off: float, t: float, front: bool) -> void:
	_quad(_trim, hxf, rot, Vector3(1.75, 1.45, 0.10), n * (wall_off + 0.01) + u_t * t, 1.55)
	var lit := _rng.randf() < 0.35
	var pane := _glass_lit if lit else _glass_dark
	_quad(pane, hxf, rot, Vector3(1.45, 1.15, 0.12), n * (wall_off + 0.035) + u_t * t, 1.55)
	# Remember the FIRST lit front pane per house as the TV-spill candidate.
	# A back-wall TV would light a yard nobody is looking at.
	if front and lit and _house_i >= 0 and _house_i < _tv_cand.size() \
			and _tv_cand[_house_i] == Vector3.INF:
		var tp := n * (wall_off + TV_OUT) + u_t * t
		_tv_cand[_house_i] = _wp(hxf, tp.x, tp.z, TV_Y)


## Weathered-wood fence: posts every ~2.4 m plus two continuous rails.
## center_l is the run's midpoint in house-local plan; `along` its direction.
func _fence_run(hxf: Transform3D, center_l: Vector3, along: Vector3, length: float) -> void:
	var rot := Basis(Vector3.UP, atan2(along.x, along.z))
	var posts := maxi(int(length / 2.4), 2)
	for k in posts + 1:
		var lp := center_l + along * (-length * 0.5 + length * float(k) / float(posts))
		_wood.append(Transform3D(hxf.basis * Basis.from_scale(Vector3(0.12, 1.12, 0.12)),
			_wp(hxf, lp.x, lp.z, 0.52)))
	for ry: float in [0.38, 0.92]:
		_wood.append(Transform3D(hxf.basis * rot * Basis.from_scale(Vector3(0.05, 0.10, length)),
			_wp(hxf, center_l.x, center_l.z, ry)))


## Backyard shed: small box + its own mini gable, jittered a few degrees off
## the house so the yard doesn't read machine-placed.
func _shed(hxf: Transform3D, lp: Vector3) -> void:
	var rot_j := Basis(Vector3.UP, _rng.randf_range(-0.18, 0.18))
	_shed_bodies.append(Transform3D(hxf.basis * rot_j * Basis.from_scale(Vector3(2.6, 2.05, 2.1)),
		_wp(hxf, lp.x, lp.z, 1.0)))
	var sc: Color = SHED_COLORS[_rng.randi_range(0, SHED_COLORS.size() - 1)]
	_shed_cols.append(_clamped(sc * _rng.randf_range(0.9, 1.05)))
	_shed_roofs.append(Transform3D(hxf.basis * rot_j,
		_wp(hxf, lp.x, lp.z, 2.35)))


## Trampoline: dark disc on four legs — the one yard-clutter archetype.
func _trampoline(hxf: Transform3D, u_t: Vector3, u_s: Vector3, lp: Vector3) -> void:
	_tramp_discs.append(Transform3D(hxf.basis, _wp(hxf, lp.x, lp.z, 0.79)))
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		var leg := lp + (u_t * cos(a) + u_s * sin(a)) * 1.25
		_tramp_legs.append(Transform3D(hxf.basis * Basis.from_scale(Vector3(0.07, 0.72, 0.07)),
			_wp(hxf, leg.x, leg.z, 0.36)))


# ============================== HELPERS ======================================
## House-local plan position (lx, lz) rotated by the house yaw, at ABSOLUTE
## world height y — heights here are all measured from ground (~0), not from
## the house box center.
func _wp(hxf: Transform3D, lx: float, lz: float, y: float) -> Vector3:
	var v := hxf.origin + hxf.basis * Vector3(lx, 0.0, lz)
	return Vector3(v.x, y, v.z)


## One scaled unit-box instance: local rotation THEN scale (the M8/M13 law:
## rot * Basis.from_scale — Basis.scaled() shears anything rotated).
func _quad(arr: Array[Transform3D], hxf: Transform3D, rot: Basis, sizev: Vector3,
		lp: Vector3, y: float) -> void:
	arr.append(Transform3D(hxf.basis * rot * Basis.from_scale(sizev),
		_wp(hxf, lp.x, lp.z, y)))


func _clamped(c: Color) -> Color:
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


## A ground-pool decal transform in WORLD space, for streetlight_glow. Local X
## is scaled to the half-axis ALONG the wall, local Z to the half-axis OUT from
## it (rot maps local +Z to the outward normal). Y is left at zero — the pool
## system owns the height stratum and overwrites it.
func _pool(hxf: Transform3D, rot: Basis, lp: Vector3, half: Vector2) -> Transform3D:
	return Transform3D(hxf.basis * rot * Basis.from_scale(Vector3(half.x, 1.0, half.y)),
		_wp(hxf, lp.x, lp.z, 0.0))


# ============================== NIGHT PASS ===================================
## Decides which houses get a driveway flood and which have a TV on. Runs after
## every house is built, off `_nrng` alone, so the day build is untouched.
## Independent coin flips in build order means the chosen houses are scattered
## across the whole plat rather than clustered at the head of the list — no cap
## is needed to spread them, only to bound the worst case.
func _night_pass() -> void:
	_nrng.seed = NIGHT_SEED
	for i in _porch_pts.size():
		_soft_pools.append(_porch_pools[i])
		if _nrng.randf() < FLOOD_CHANCE:
			_flood_pts.append(_flood_cand[i])
			_soft_pools.append(_flood_pools[i])
		if _nrng.randf() < TV_CHANCE and _tv_pts.size() < TV_CAP \
				and i < _tv_cand.size() and _tv_cand[i] != Vector3.INF:
			_tv_pts.append(_tv_cand[i])


# ========================== NIGHT CONTRACT (D-014) ===========================
## Read-only records for suburb_night.gd. No rng replay, no node lookups: the
## arrays are already built by the time any system's setup() runs.
func get_porch_light_points() -> Array[Vector3]:
	return _porch_pts.duplicate()


func get_flood_light_points() -> Array[Vector3]:
	return _flood_pts.duplicate()


func get_tv_light_points() -> Array[Vector3]:
	return _tv_pts.duplicate()


## Contract for streetlight_glow.gd: soft ground pools that are NOT under a
## cobra head. These carry the district after the OmniLights distance-fade —
## the far half of a suburb vista is decals, the near half is real light.
func get_light_pool_xfs() -> Array[Transform3D]:
	return _soft_pools.duplicate()


## Night dimmer for the two emissive materials this file owns. ONE property
## write per material per call, and the caller only calls when the level
## actually moves — this is O(1) per frame, never O(houses).
## level 0 leaves the day build EXACTLY as it shipped.
func set_night_level(level: float) -> void:
	var k := clampf(level, 0.0, 1.0)
	if _porch_mat != null:
		_porch_mat.emission_energy_multiplier = lerpf(PORCH_DAY_E, PORCH_NIGHT_E, k)
	if _lit_mat != null:
		_lit_mat.emission_energy_multiplier = lerpf(LIT_DAY_E, LIT_NIGHT_E, k)


# ============================== FLUSH ========================================
func _flush() -> void:
	for key: String in _roofs.keys():
		var g: Dictionary = _roofs[key]
		# Roofs cast: they ARE the house's silhouette against the sun, and the
		# 492-light district is read at 22 m from the suburb vantage where the
		# eave shadow on the wall below is the only thing giving depth.
		_mm(g["mesh"] as Mesh, g["xf"] as Array[Transform3D],
			g["col"] as Array[Color], _tinted(0.95), "SuburbRoofs_" + key, true)
	_mm(_unit, _chimneys, _no_cols, _flat(Color(0.40, 0.27, 0.21), 0.9),
		"Chimneys", true)
	# OFF — everything below is a 0.10 m frame, a 0.12 m door leaf or a pane set
	# 10-35 mm proud of a house wall that is ALREADY casting the house's shadow.
	# 3,247 instances of relief that can only shade the surface it is glued to.
	# (Lit glass is the sharpest case: a window that is emitting light at night
	# has no business being an occluder in the sun's cascade.)
	_mm(_unit, _trim, _no_cols, _flat(Color(0.87, 0.85, 0.79), 0.85),
		"FacadeTrim", false)
	_mm(_unit, _doors, _door_cols, _tinted(0.7), "FrontDoors", false)
	_mm(_unit, _garages, _no_cols, _flat(Color(0.78, 0.76, 0.71), 0.75),
		"GarageDoors", false)
	_mm(_unit, _glass_dark, _no_cols, _glass_mat(false), "HouseGlassDark", false)
	_lit_mat = _glass_mat(true)
	_mm(_unit, _glass_lit, _no_cols, _lit_mat, "HouseGlassLit", false)
	_porch_mat = _make_porch_mat()
	_mm(_unit, _porch, _no_cols, _porch_mat, "PorchLights", false)
	# Driveway (40 mm), walk (40 mm) and caliche apron (30 mm) are ground.
	_mm(_unit, _concrete, _no_cols, _flat(Color(0.55, 0.54, 0.51), 0.95),
		"Driveways", false)
	_mm(_unit, _aprons, _no_cols, _flat(Color(0.41, 0.35, 0.25), 1.0),
		"DirtAprons", false)
	# THE BIG ONE OUT HERE: 3,255 instances, and not one of them is solid. This
	# is a post-and-rail fence — 0.12 m posts and 0.05 x 0.10 m rails — plus the
	# mailbox posts. Its shadow is a comb of hairlines the cascade cannot hold
	# without shimmering, and it was dragging the whole subdivision's fencing
	# into every frame the moment one picket was on screen.
	_mm(_unit, _wood, _no_cols, _flat(Color(0.44, 0.37, 0.28), 0.95),
		"FenceWood", false)
	# Standing props keep theirs: a mailbox head, a shed, a trampoline.
	_mm(_unit, _mail_heads, _no_cols, _flat(Color(0.19, 0.20, 0.22), 0.6),
		"Mailboxes", true)
	_mm(_unit, _shed_bodies, _shed_cols, _tinted(0.9), "ShedBodies", true)
	var shed_roof: ArrayMesh = MESH_KIT.taper(Vector3(3.0, 0.65, 2.5), Vector2(3.0, RIDGE_W))
	_mm(shed_roof, _shed_roofs, _no_cols, _flat(Color(0.23, 0.22, 0.22), 0.95),
		"ShedRoofs", true)
	var disc: ArrayMesh = MESH_KIT.prism(1.75, 0.14, 12)
	_mm(disc, _tramp_discs, _no_cols, _flat(Color(0.10, 0.11, 0.14), 0.6),
		"TrampolineDiscs", true)
	_mm(_unit, _tramp_legs, _no_cols, _flat(Color(0.25, 0.26, 0.28), 0.6),
		"TrampolineLegs", true)


func _flat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _tinted(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


## House window glass: dark blue-grey (never near-black — the D-013 hole
## lesson) with a little reflectivity; the lit variant adds a warm interior
## glow peaking at 0.88 — under the 1.05 HDR bloom threshold.
func _glass_mat(lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.14, 0.16)
	m.roughness = 0.16
	m.metallic = 0.22
	m.metallic_specular = 0.55
	if lit:
		m.emission_enabled = true
		m.emission = Color(0.92, 0.68, 0.38)
		m.emission_energy_multiplier = LIT_DAY_E
	return m


## Porch light: the one deliberately HDR emissive out here (1.6 > the 1.05
## bloom threshold) — a tiny fixture, so it blooms as a point, and the night
## suburb becomes a constellation of porch lights. set_night_level() lifts it
## to PORCH_NIGHT_E after dusk so the fixture still reads at 150 m, where the
## OmniLight that goes with it has already distance-faded to nothing.
func _make_porch_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.78, 0.55)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.45)
	m.emission_energy_multiplier = PORCH_DAY_E
	return m


## `casts` is required, no default (D-028): a MultiMesh is frustum-culled as
## ONE unit, so one visible fence post put all 3,255 of them in every cascade.
func _mm(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color],
		m: StandardMaterial3D, label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = m
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
