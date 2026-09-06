extends RefCounted
## OBJECTIVE BEACON KIT — the one look every "go here" marker in the game
## shares (repo target, both mission boards, both mission targets).
##
## ── CYCLE 1 (D-015): what it replaced ────────────────────────────────────────
## Three systems each grew their own marker and all three reached for the same
## wrong shape: an axis-aligned BoxMesh 60–80 m tall, the same width at the top
## as at the bottom, no vertical falloff. That is not a beam of light, it is
## scaffolding. It ran through 31 of 36 review vantages.
##
## ── CYCLE 4 (D-032): what was STILL wrong, and what it cost ──────────────────
## The short version: the beacon was a sheet of smoked orange glass, not light.
## It caused three cycles of mis-diagnosis (a "gold-tan ellipsoid on Book's
## cheek", an "orange tree canopy", "glitchy buildings") because it repainted
## whatever stood behind it and everybody blamed the thing being repainted.
##
## FOUR mechanisms, measured, not guessed (frozen-world differential render:
## the same 59 vantages with the beacon on and with it hidden, noise floor 1.0):
##
##  1. WRONG BLEND. `TRANSPARENCY_ALPHA` defaults to MIX:
##        out = src·a + dst·(1−a)
##     so every covered pixel was 34 % replaced by orange AND the background it
##     replaced was crushed to 66 %. The tell is the blue channel: the veil
##     measured dR +16..+32 / dG −1..+6 / **dB −6..−7**. An additive light
##     source CANNOT subtract blue. That single sign settles the mechanism.
##     Worse, in daylight the median luminance change over the covered pixels
##     was **−0.2** — at noon the old beacon added no light at all, it only
##     re-tinted. It was not a beam. It was a filter.
##
##  2. NO DISTANCE TERM. Per-pixel opacity was constant in range while screen
##     coverage grows as 1/d², so the beacon's damage was *maximised at exactly
##     the range where the player least needs it* — standing on top of it. From
##     11 m it repainted 80,693 px (5.6 % of the frame; 110,920 px at night).
##     From 371 m — the impound pad, the range it exists for — it reached 43 px
##     and was NOT FINDABLE in daylight. The budget was spent backwards.
##
##  3. TOP RAMP TOO WEAK. `pow(v, 1.75)` still carries ~0.10 alpha at half
##     height over 21 m of shaft, which is why QA kept re-photographing "a soft
##     salmon column over the sky" in the character and vehicle vantages.
##
##  4. THE CORONA COULD NOT CARRY. At 3.4 m radius it was too small to be the
##     close-range read, so the column had to do a job it is bad at.
##
## ── THE RULES THIS KIT NOW HOLDS ─────────────────────────────────────────────
## A. A BEACON NEVER SUBTRACTS LIGHT. `BLEND_MODE_ADD`. It is emissive
##    participating media; it can brighten what is behind it and nothing else.
##    Background texture, hue and contrast survive underneath it by
##    construction, so it can no longer be mistaken for a defect in the thing
##    it stands in front of.
## B. THE COLUMN IS A LONG-RANGE INSTRUMENT AND FADES OUT WHEN YOU ARRIVE.
##    Intensity is driven from camera distance to the beacon's FOOT (`Driver`):
##    zero at NEAR_HIDE, full at NEAR_FULL, boosted to FAR_GAIN by FAR_FULL.
##    The screen-space cost of a marker rises as you approach it and its value
##    falls — so the intensity has to run the other way.
## C. THE CORONA CARRIES CLOSE RANGE. Ground-locked, so it can never veil a
##    subject: it lights the road the target stands on and nothing else.
## D. IT IS OCCLUDED BY GEOMETRY, ON PURPOSE. Depth-test stays ON. A shaft that
##    draws over the tower in front of it is a screen-space veil *by
##    definition* and would re-open this defect on day one; it would also
##    destroy the depth read of downtown. The see-through job already belongs to
##    the HUD — `repo_board._update_ui()` prints a compass arrow and a live
##    metre count that no building can hide. World light obeys the world.
##
## HOW IT IS BUILT (100 % code, zero asset files, per project doctrine):
##  * the column is ONE Y-billboard quad — always camera-facing, so it can never
##    show a facet, a corner or a hard silhouette edge, and it thins toward
##    invisible seen from directly overhead, which is what `aerial` wanted;
##  * its shape lives in a generated RGBA ramp: alpha reaches ZERO before the
##    top edge and off both flanks, and the lit core narrows with height;
##  * colour is EMISSION over a BLACK albedo with ambient and specular off, so a
##    beacon looks identical at noon and at 3 a.m. and never takes lighting;
##  * the ground corona is a flat ring on the paint plane, same discipline.
##
## Two textures total, built once at first use and shared by every beacon in the
## game. The only per-frame work is one float compare per beacon (five in the
## whole project) — never per-instance work over a batched set.

# The ramp is authored TOP-DOWN because QuadMesh puts UV v=0 at the top edge.
const RAMP_W := 64
const RAMP_H := 128
const RING_PX := 96

# ── TUNING KNOBS: the distance response (rule B) ─────────────────────────────
# Playtest hypotheses, stated as numbers somebody can argue with:
# NEAR_HIDE is set from the measurement, not from taste: every one of the 12
# judgement vantages and every showcase vantage stands 15.8–28.2 m from the repo
# target, and a marker has nothing to tell you at 26 m that the ground corona
# and the target's own pulse are not already saying louder.
const NEAR_HIDE := 26.0     # m — column contributes exactly nothing at/below
const NEAR_FULL := 100.0    # m — column at base intensity at/above
const FAR_FULL := 260.0     # m — distance at which FAR_GAIN is reached
const FAR_GAIN := 4.2       # × base. The old beacon's median luminance change
                            # at 157 m in daylight was -0.2: it added no light
                            # at all across downtown, which is the one range it
                            # exists for. This is where its budget went instead.
# ── TUNING KNOBS: the shaft profile (rule A/C) ───────────────────────────────
const TOP_FEATHER := 0.07   # fraction of the shaft that is hard zero at the top
const TOP_POWER := 2.2      # higher = the shaft dies lower down
# The corona's peak alpha came DOWN from 0.55 in the same pass that un-buried
# it. Additive light on sunlit asphalt is far louder than the old MIX blend was:
# at 0.42 the corona alone put +72 R over 10,611 px into `showcase_cars` and
# simply became the new thing painting the frame; at 0.18 it was still +42 R
# over 10,091 px there. 0.12 lights the road the target stands on and still
# leaves the 11 m read at 2.2x the findability floor (95th-pct luminance lift
# 32.7 against a floor of 15.0).
const RING_ALPHA := 0.12

static var _ramp_tex: ImageTexture = null
static var _ring_tex: ImageTexture = null


## Drives one beacon's column intensity from camera range (rule B). Attached to
## the beacon ROOT, whose origin is the ground point being marked — so the fade
## is keyed to the beacon's FOOT, not to whichever fragment of a 21 m billboard
## happens to be nearest the lens. (That is why `BaseMaterial3D`'s built-in
## distance fade is not used: it is per-fragment, so on a tall shaft it fades
## the bottom while leaving the top lit — backwards.)
class Driver extends Node3D:
	var column_mesh: MeshInstance3D = null
	var column_mat: StandardMaterial3D = null
	var base_energy := 1.0
	# Mirrors of the file constants above; `beacon()` writes the real values.
	var near_hide := 26.0
	var near_full := 100.0
	var far_full := 260.0
	var far_gain := 4.2
	var _last := -1.0

	## Camera range → column gain. Public and pure so it can be unit-checked.
	func gain_at(d: float) -> float:
		var g := smoothstep(near_hide, near_full, d)
		if g <= 0.0:
			return 0.0
		var span: float = maxf(far_full - near_full, 1.0)
		return g * lerpf(1.0, far_gain, clampf((d - near_full) / span, 0.0, 1.0))

	func _process(_delta: float) -> void:
		if column_mat == null or not is_visible_in_tree():
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var g := gain_at(global_position.distance_to(cam.global_position))
		if absf(g - _last) < 0.002:
			return
		_last = g
		column_mat.emission_energy_multiplier = base_energy * g
		if column_mesh != null:
			column_mesh.visible = g > 0.002


## The column: a soft-edged, top-faded, upward-tapering shaft of light standing
## on the beacon's origin. `height` is the FULL height above the ground plane.
static func column(color: Color, height: float, width: float,
		peak_alpha: float, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	q.center_offset = Vector3(0.0, height * 0.5, 0.0)   # pivot at the FOOT
	mi.mesh = q
	mi.material_override = column_material(color, peak_alpha, energy)
	# A billboarded quad rotates outside the mesh AABB the renderer culls
	# against; without the margin the shaft pops out at oblique angles.
	mi.extra_cull_margin = maxf(width, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The ground corona: a flat ring lying on the road at the beacon's foot. This
## is what reads from directly above and from two metres away, the two ranges
## the column deliberately gives up (rule C). It is NOT distance-driven: it is
## ground-locked, so it can never paint over the thing you are looking at.
static func corona(color: Color, radius: float, energy: float,
		peak_alpha := RING_ALPHA) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = q
	mi.rotation.x = -PI * 0.5                            # lay it flat, face up
	mi.position.y = 0.062                                # over the 0.045 paint plane
	mi.material_override = ring_material(color, peak_alpha, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Column + corona under one Driver node. Move it by setting `position` to the
## GROUND point you are marking — no half-height bookkeeping at the call site.
## `ring_alpha < 0.0` keeps the kit default.
static func beacon(color: Color, height: float, width: float,
		peak_alpha: float, energy: float, ring_radius: float,
		ring_alpha := -1.0) -> Node3D:
	var root := Driver.new()
	root.add_to_group("objective_beacon")
	root.base_energy = energy
	root.near_hide = NEAR_HIDE
	root.near_full = NEAR_FULL
	root.far_full = FAR_FULL
	root.far_gain = FAR_GAIN
	var col := column(color, height, width, peak_alpha, energy)
	root.column_mesh = col
	root.column_mat = col.material_override as StandardMaterial3D
	# Start dark: the Driver writes the real value on its first frame, and a
	# beacon that pops in at full intensity for one frame is a flash bug.
	root.column_mat.emission_energy_multiplier = 0.0
	col.visible = false
	root.add_child(col)
	if ring_radius > 0.0:
		root.add_child(corona(color, ring_radius, energy,
			ring_alpha if ring_alpha >= 0.0 else RING_ALPHA))
	return root


# ============================== MATERIALS ====================================
## Black albedo + emission: the fragment colour is the emission, full stop.
## Ambient off and specular zeroed so no light in the world can change it, and
## the alpha ramp in the albedo texture fades the WHOLE fragment to nothing at
## the top. BLEND_MODE_ADD is rule A and is the whole fix for D-032: the
## fragment is `dst + emission·energy·alpha`, so nothing behind a beacon is ever
## replaced, dimmed, or hue-shifted — only lit.
static func column_material(color: Color, peak_alpha: float,
		energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0, 0.0, 0.0, peak_alpha)
	m.albedo_texture = _ramp()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	# No emission TEXTURE here, so the flat colour is the whole emission (the
	# emission_operator ADD trap only bites when a texture is present).
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.disable_ambient_light = true
	m.disable_receive_shadows = true
	return m


static func ring_material(color: Color, peak_alpha: float,
		energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0, 0.0, 0.0, peak_alpha)
	m.albedo_texture = _ring()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.disable_ambient_light = true
	m.disable_receive_shadows = true
	return m


# ============================== TEXTURES =====================================
## Alpha ramp for the shaft. v runs 0 (top of the quad) to 1 (the ground). The
## vertical term is hard ZERO for the top TOP_FEATHER of the quad and then rises
## as a power, so the shaft dissolves well below its own top edge instead of
## being cut off — that is what stops it reaching the skyline. The horizontal
## profile is a bright narrow core inside a wide soft skirt, and BOTH narrow as
## the shaft rises: that is the taper.
static func _ramp() -> ImageTexture:
	if _ramp_tex != null:
		return _ramp_tex
	var img := Image.create(RAMP_W, RAMP_H, true, Image.FORMAT_RGBA8)
	for py in RAMP_H:
		var v := float(py) / float(RAMP_H - 1)          # 0 = top, 1 = foot
		var vertical := pow(clampf((v - TOP_FEATHER) / (1.0 - TOP_FEATHER),
			0.0, 1.0), TOP_POWER)
		var half := lerpf(0.34, 1.0, pow(v, 0.65))      # core half-width, in u
		for px in RAMP_W:
			var u := (float(px) + 0.5) / float(RAMP_W)
			var d := absf(u - 0.5) / maxf(0.5 * half, 0.001)
			var skirt := clampf(1.0 - d * d, 0.0, 1.0)
			skirt *= skirt
			var core := exp(-pow(d * 2.5, 2.0))
			var a := vertical * clampf(0.40 * skirt + 0.60 * core, 0.0, 1.0)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
	img.generate_mipmaps()
	_ramp_tex = ImageTexture.create_from_image(img)
	return _ramp_tex


## Ground corona: a soft annulus with a faint wash inside it, zero outside the
## radius so the quad's corners never show.
static func _ring() -> ImageTexture:
	if _ring_tex != null:
		return _ring_tex
	var img := Image.create(RING_PX, RING_PX, true, Image.FORMAT_RGBA8)
	var c := float(RING_PX - 1) * 0.5
	for py in RING_PX:
		for px in RING_PX:
			var r := Vector2(float(px) - c, float(py) - c).length() / maxf(c, 1.0)
			var band := exp(-pow((r - 0.80) / 0.115, 2.0))
			var wash := 0.16 * clampf(1.0 - r / 0.86, 0.0, 1.0)
			var a := clampf(band + wash, 0.0, 1.0) * clampf((1.0 - r) / 0.08, 0.0, 1.0)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
	img.generate_mipmaps()
	_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex
