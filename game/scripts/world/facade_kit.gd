extends RefCounted
## FACADE KIT (M14) — storefront depth for the retail podiums, 100% code.
## The podium boxes shipped as flat brick; this kit gives their ground floors
## real retail bays: a stone bulkhead, dark glazing panels PROUD of the wall
## (the lofted-hull lesson — recessed panels vanish, glass must sit slightly
## proud), pilasters between bays, one door bay with a step and an electrical
## conduit box, fabric awning wedges with actual depth (mesh_kit taper, color
## per podium from a muted palette), a colored fascia band where the signage
## would live, AC/vent clutter on the canopy rim, and a few blade signs over
## the two main drags carrying canon §7 brand names ONLY.
##
## CONTRACT: visual-only (zero collision), MultiMesh everything repeated (the
## only per-node elements are the blade-sign labels), and no shared-RNG draws —
## the caller hands in a fresh seeded RNG. rot * Basis.from_scale throughout;
## never Basis.scaled on a rotated box.

const SIGN := preload("res://scripts/world/sign_kit.gd")
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const TEX := preload("res://scripts/world/city_textures.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

const GROUND := 0.2                            # block slab top — the sidewalk
const MAIN_X: Array[float] = [193.0, 451.0]    # blade-sign streets (busiest)
const BLADE_CAP := 18
# Near-quadrant podium faces sit 12.25-23.25 m off the street centreline
# (quadrant 28 +/- 3 jitter minus half-width 7.75-12.75) — the match window
# must cover the whole band or almost no face ever qualifies (round-1 shot
# review: zero blade signs rendered at a 16.5 window; probe counted 5 at 18.5).
const BLADE_MATCH := 24.0
const BLADE_NAME_MAX := 12                     # longer canon names turn to mush
# Awning + fascia palettes: muted North Texas retail — nothing saturated.
const AWNING_COLORS: Array[Color] = [
	Color(0.45, 0.13, 0.12), Color(0.14, 0.30, 0.19), Color(0.15, 0.21, 0.35),
	Color(0.60, 0.31, 0.13), Color(0.72, 0.66, 0.52), Color(0.16, 0.34, 0.34)]
const FASCIA_COLORS: Array[Color] = [
	Color(0.17, 0.16, 0.15), Color(0.25, 0.20, 0.14), Color(0.15, 0.21, 0.17),
	Color(0.30, 0.15, 0.13), Color(0.21, 0.23, 0.25)]


static func build(parent: Node3D, podiums: Array[Transform3D],
		rng: RandomNumberGenerator, shops: Array) -> void:
	var bulk: Array[Transform3D] = []
	var glass_dark: Array[Transform3D] = []
	var glass_lit: Array[Transform3D] = []
	var pilasters: Array[Transform3D] = []
	var fascia_xf: Array[Transform3D] = []
	var fascia_col: Array[Color] = []
	var awn_xf: Array[Transform3D] = []
	var awn_col: Array[Color] = []
	var doors: Array[Transform3D] = []
	var steps: Array[Transform3D] = []
	var conduits: Array[Transform3D] = []
	var acs: Array[Transform3D] = []
	var fans: Array[Transform3D] = []
	var vents: Array[Transform3D] = []
	var blades: Array[Transform3D] = []
	var blade_col: Array[Color] = []
	var brackets: Array[Transform3D] = []
	var blade_count := 0
	var shop_i := 0
	var faces: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for xf: Transform3D in podiums:
		# Podium record: Basis.IDENTITY.scaled(size), axis-aligned by contract.
		var half := Vector3(xf.basis.x.x, xf.basis.y.y, xf.basis.z.z) * 0.5
		var c := xf.origin
		var awn_c: Color = AWNING_COLORS[rng.randi_range(0, AWNING_COLORS.size() - 1)]
		var fas_c: Color = FASCIA_COLORS[rng.randi_range(0, FASCIA_COLORS.size() - 1)]
		var has_awn := rng.randf() < 0.75
		# --- Rooftop clutter: the canopy rim ring (tower shaft owns the middle,
		# the canopy overhangs 0.8 m — the strip between is the podium's roof).
		for _k in rng.randi_range(2, 4):
			var rn: Vector3 = faces[rng.randi_range(0, 3)]
			var rhn := absf(rn.x) * half.x + absf(rn.z) * half.z
			var rht := absf(rn.x) * half.z + absf(rn.z) * half.x
			var rt := Vector3(rn.z, 0.0, -rn.x)
			var rtoff := rng.randf_range(-(rht - 1.0), rht - 1.0)
			var rpos := Vector3(c.x, 0.0, c.z) + rn * (rhn - 0.13) + rt * rtoff
			var ryaw := atan2(rn.x, rn.z) + rng.randf_range(-0.07, 0.07)
			acs.append(Transform3D(Basis(Vector3.UP, ryaw)
				* Basis.from_scale(Vector3(0.85, 0.6, 0.85)), rpos + Vector3(0, 8.075, 0)))
			fans.append(Transform3D(Basis.from_scale(Vector3(0.31, 0.08, 0.31)),
				rpos + Vector3(0, 8.415, 0)))
			if rng.randf() < 0.4:
				var vtoff := rng.randf_range(-(rht - 1.0), rht - 1.0)
				vents.append(Transform3D(Basis(Vector3.UP, ryaw)
					* Basis.from_scale(Vector3(0.13, 1.1, 0.13)),
					Vector3(c.x, 0.0, c.z) + rn * (rhn - 0.13) + rt * vtoff
					+ Vector3(0, 8.325, 0)))
		# --- The four street walls: bays, pilasters, fascia, door, awnings.
		for n: Vector3 in faces:
			var half_n := absf(n.x) * half.x + absf(n.z) * half.z
			var half_t := absf(n.x) * half.z + absf(n.z) * half.x
			var w := half_t * 2.0
			var t := Vector3(n.z, 0.0, -n.x)
			var rot := Basis(Vector3.UP, atan2(n.x, n.z))  # local +Z -> n, +X -> t
			var fp := Vector3(c.x + n.x * half_n, 0.0, c.z + n.z * half_n)
			var nb := clampi(int((w - 1.2) / 3.4), 2, 7)
			var usable := w - 0.9
			var pitch := usable / float(nb)
			var door_bay := rng.randi_range(0, nb - 1)
			for k in nb + 1:  # pilasters at every bay boundary
				pilasters.append(_pt(rot, Vector3(0.44, 4.1, 0.34), fp, t,
					-usable * 0.5 + pitch * float(k), n, 0.05, 2.25))
			fascia_xf.append(_pt(rot, Vector3(w, 0.9, 0.36), fp, t, 0.0, n, 0.0, 3.85))
			fascia_col.append(fas_c)
			for k in nb:
				var bc := -usable * 0.5 + pitch * (float(k) + 0.5)
				var gw := pitch - 0.62
				if k == door_bay:
					doors.append(_pt(rot, Vector3(minf(gw, 2.6), 3.18, 0.16),
						fp, t, bc, n, 0.0, GROUND + 1.59))
					steps.append(_pt(rot, Vector3(minf(gw, 2.2), 0.12, 0.5),
						fp, t, bc, n, 0.3, GROUND + 0.06))
					if rng.randf() < 0.8:  # conduit box on the flanking pilaster
						var cs := 1.0 if rng.randf() < 0.5 else -1.0
						conduits.append(_pt(rot, Vector3(0.34, 0.5, 0.16), fp, t,
							bc + cs * (gw * 0.5 + 0.31), n, 0.24, 1.35))
				else:
					bulk.append(_pt(rot, Vector3(gw, 0.58, 0.26),
						fp, t, bc, n, 0.02, GROUND + 0.29))
					var gxf := _pt(rot, Vector3(gw, 2.6, 0.2),
						fp, t, bc, n, 0.03, GROUND + 1.88)
					if rng.randf() < 0.45:
						glass_lit.append(gxf)
					else:
						glass_dark.append(gxf)
					if has_awn and rng.randf() < 0.6:
						awn_xf.append(_pt(rot, Vector3(gw + 0.2, 0.55, 1.35),
							fp, t, bc, n, 0.62, 3.32))
						var ac2 := awn_c * rng.randf_range(0.85, 1.05)
						awn_col.append(Color(minf(ac2.r, 1.0), minf(ac2.g, 1.0),
							minf(ac2.b, 1.0), 1.0))  # HDR law: >1 reads as glow
			# --- Blade sign, only on faces looking onto a main drag.
			if blade_count < BLADE_CAP and n.x != 0.0:
				for sxv: float in MAIN_X:
					if absf(fp.x - sxv) < BLADE_MATCH and signf(sxv - c.x) == signf(n.x) \
							and rng.randf() < 0.9:
						var e: Array = shops[shop_i % shops.size()]
						while (e[0] as String).length() > BLADE_NAME_MAX:
							shop_i += 1
							e = shops[shop_i % shops.size()]
						shop_i += 1
						blade_count += 1
						_blade(parent, blades, blade_col, brackets, rot, fp, t, n, e)
						break
	# --- Flush: one MultiMesh (one draw call) per element type.
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var wedge: ArrayMesh = MESH_KIT.taper(Vector3.ONE, Vector2(1.0, 0.05),
		Vector2(0.0, -0.475))  # top face is a thin strip at the wall edge
	var disc: ArrayMesh = MESH_KIT.prism(1.0, 1.0, 10)
	# SHADOW POLICY (D-028). Everything in this kit is relief BOLTED TO a podium
	# wall that already casts the building's shadow, so the default here is OFF:
	# a 0.16 m door recessed in a bay, a 0.02 m bulkhead, glazing flush in the
	# opening and a 0.12 m step slab on the pavement all cast onto the surface
	# they are already touching, which is shadow acne, not shading. The three
	# exceptions are the pieces that stand OUT into daylight over the sidewalk.
	_install_night_driver(parent)
	_mm(parent, unit, bulk, [], _flat(Color(0.22, 0.20, 0.18), 0.85),
		"StoreBulkheads", false)
	_mm(parent, unit, glass_dark, [], SHD.storefront_glass(false),
		"StoreGlassDark", false)
	_mm(parent, unit, glass_lit, [], SHD.storefront_glass(true),
		"StoreGlassLit", false)
	_mm(parent, unit, pilasters, [], _flat(Color(0.24, 0.21, 0.18), 0.9),
		"StorePilasters", false)
	_mm(parent, unit, fascia_xf, fascia_col, _tinted(0.8), "StoreFascias", false)
	# ON: the awning is the one piece with 1.35 m of overhang at 3.3 m, and the
	# band of shade it lays on the sidewalk is what makes a storefront read as
	# sheltered rather than painted on. 385 instances, and worth every one.
	_mm(parent, wedge, awn_xf, awn_col, _tinted(1.0), "StoreAwnings", true)
	_mm(parent, unit, doors, [], _flat(Color(0.13, 0.15, 0.16), 0.4, 0.2),
		"StoreDoors", false)
	_mm(parent, unit, steps, [], _flat(Color(0.50, 0.49, 0.46), 0.9),
		"StoreSteps", false)
	_mm(parent, unit, conduits, [], _flat(Color(0.35, 0.36, 0.38), 0.6, 0.4),
		"ConduitBoxes", false)
	# ON: rooftop AC is free-standing mass on an open deck, and its shadows are
	# most of what stops a podium roof reading as a flat gray lid from a tower
	# window or the aerial vantage. The 80 mm fan disc sitting on top of it and
	# the 0.13 m vent stack are detail ON a caster, so they stay off.
	_mm(parent, unit, acs, [], _flat(Color(0.58, 0.58, 0.56), 0.8),
		"PodiumAC", true)
	_mm(parent, disc, fans, [], _flat(Color(0.20, 0.20, 0.22), 0.7),
		"PodiumACFans", false)
	_mm(parent, unit, vents, [], _flat(Color(0.48, 0.48, 0.50), 0.7, 0.3),
		"PodiumVents", false)
	# ON: a blade sign hangs 1.8 m clear of the wall at 5.2 m — the shadow
	# crossing the sidewalk is the whole point of a projecting sign, and there
	# are only 13. Its 90 mm brackets are hairlines and stay off.
	_mm(parent, unit, blades, blade_col, _tinted(0.75), "BladeSigns", true)
	_mm(parent, unit, brackets, [], _flat(Color(0.15, 0.15, 0.16), 0.7),
		"BladeBrackets", false)


## One proud wall element: local X along the face (t), local Z out the wall (n).
## depth is the CENTER offset along n from the wall plane; y is the center height.
static func _pt(rot: Basis, scale: Vector3, fp: Vector3, t: Vector3, toff: float,
		n: Vector3, depth: float, y: float) -> Transform3D:
	return Transform3D(rot * Basis.from_scale(scale),
		Vector3(fp.x + t.x * toff + n.x * depth, y, fp.z + t.z * toff + n.z * depth))


## Blade sign: two wall brackets + a double-faced colored panel perpendicular
## to the facade, canon name on both sides. The labels are the only per-node
## cost in this kit (Label3D is unshaded — it reads at night for free).
static func _blade(parent: Node3D, blades: Array[Transform3D],
		blade_col: Array[Color], brackets: Array[Transform3D], rot: Basis,
		fp: Vector3, t: Vector3, n: Vector3, e: Array) -> void:
	var base := Vector3(fp.x, 0.0, fp.z)
	for by: float in [4.85, 5.55]:
		brackets.append(Transform3D(rot * Basis.from_scale(Vector3(0.09, 0.09, 0.5)),
			base + n * 0.25 + Vector3(0, by, 0)))
	blades.append(Transform3D(rot * Basis.from_scale(Vector3(0.12, 0.95, 2.6)),
		base + n * 1.8 + Vector3(0, 5.2, 0)))
	blade_col.append(e[1])
	# M22: a projecting blade is 2.6 m long and 0.95 m TALL, but the old rule
	# only ever solved for width on one line — so LONGHORN WRECKER & RECOVERY
	# came out at 14 pt, filling 11 % of the board's height, on a sign whose
	# entire job is to be read down the sidewalk. Long names break onto two
	# lines and are then free to grow into the board they are actually on.
	var blade_txt := SIGN.balance(str(e[0]), 2) if str(e[0]).length() > 12 \
		else str(e[0])
	for sidef: float in [1.0, -1.0]:
		var lbl := SIGN.make(blade_txt, SIGN.FASCIA, e[2], 2.36, 0.80, 46)
		lbl.position = base + n * 1.8 + t * (sidef * 0.08) + Vector3(0, 5.2, 0)
		var d := t * sidef
		lbl.rotation.y = atan2(d.x, d.z)
		parent.add_child(lbl)


static func _flat(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func _tinted(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


## `casts` is required, no default: a MultiMesh is culled as one unit, so a
## single visible storefront drags all 1,328 pilasters into every shadow
## cascade. See the policy block at the flush above.
static func _mm(parent: Node3D, mesh: Mesh, xf: Array[Transform3D],
		cols: Array[Color], m: Material, label: String,
		casts: bool) -> void:
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
	parent.add_child(mmi)


# ========================== THE SHOP-WINDOW NIGHT RAMP =======================
## M23. The interior-mapped storefront glass reads a `night_level` global; this
## is the one thing in the project that writes it. It is deliberately a node in
## THIS file rather than an edit to `sky_weather.gd` or `main.gd`, which belong
## to another mission (D-029): the kit that owns the material owns the driver
## for it, and the driver is deleted with the kit if the kit ever goes.
##
## Cost is one float compare per frame and, on the frames the level actually
## moves, ONE global write — the same shape as `downtown_types.set_night_level`
## and for the same reason (§4b: no per-frame work that scales with instances).
## `level_for_hour` is `streetlight_glow`'s own, so the shop windows come up at
## the same minute the streetlights, the suburb, the freeway and downtown do
## instead of inventing a fifth opinion about when dusk is.
class NightDriver extends Node:
	const GLOW := preload("res://scripts/systems/streetlight_glow.gd")
	# inner classes preload their own kits (M23); the outer preload is not visible here
	const SHADERS := preload("res://scripts/world/city_shaders.gd")  # gdlint:ignore=duplicated-load
	const TEXK := preload("res://scripts/world/city_textures.gd")  # gdlint:ignore=duplicated-load
	var _sky: Node = null
	var _lvl := -1.0

	func _process(_d: float) -> void:
		if _sky == null or not is_instance_valid(_sky):
			_sky = _find_sky()
			if _sky == null:
				return
		var tv: Variant = _sky.get("time_of_day")
		if not (tv is float):
			return
		var lvl: float = GLOW.level_for_hour(tv as float)
		if absf(lvl - _lvl) > 0.0005:
			_lvl = lvl
			SHADERS.set_night_level(lvl)
			TEXK.set_night_level(lvl)  # D-104: greybox/hospital windows and lit storefronts

	func _find_sky() -> Node:
		var n: Node = get_parent()
		while n != null:
			var sys: Variant = n.get("systems")
			if sys is Dictionary:
				var sk: Variant = (sys as Dictionary).get("sky_weather")
				if sk is Node and is_instance_valid(sk):
					return sk as Node
			n = n.get_parent()
		return null


static func _install_night_driver(parent: Node3D) -> void:
	# (D-104) installed in every arm: it now drives the lit-window night level too.
	if parent.get_node_or_null(NodePath("StoreNightDriver")) != null:
		return
	var d := NightDriver.new()
	d.name = "StoreNightDriver"
	parent.add_child(d)
