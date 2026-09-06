extends RefCounted
## THE RENDER PIPELINE KIT — every global light decision in the game, in one
## readable file. `main.gd::_build_environment()` is now three lines that call
## `build(self)`; everything below is what those three lines mean.
##
## ── WHY A KIT AND NOT 50 LINES IN main.gd ────────────────────────────────────
## Because every one of these features has to be separately switchable. This
## project has no VCS, a dev machine that measured the same build at 8.33 ms and
## 14.29 ms twenty minutes apart, and three agents booting Godot at once. The
## ONLY honest way to price a renderer feature here is to run both arms out of
## ONE tree, minutes apart, interleaved — exactly the argument `--perf-mm-cast=`
## makes in docs/tech/rendering/shadow-policy.md. So:
##
##   godot -- --perf --perf-repeat=3                 arm B: the new pipeline
##   godot -- --perf --perf-repeat=3 --env-legacy    arm A: byte-for-byte the
##                                                   pre-M23 environment
##   godot -- --perf --perf-repeat=3 --env-no-sdfgi  price ONE feature
##   godot -- --shot --env-legacy                    the same for the 59 plates
##
## `--env-legacy` does NOT read project.godot. Before this pass `[rendering]`
## held exactly one line (`msaa_3d=3`), so "today's environment" is the engine
## defaults plus that. Those defaults are the `LEGACY_*` constants below, applied
## by `_apply_gpu_state(host, true)`, so legacy stays exact no matter what
## `[rendering]` grows to later.
##
## ── WHAT IS ON, AND THE ONE-LINE REASON ──────────────────────────────────────
##  SDFGI      the world is generated at boot, so nothing can be baked. SDFGI is
##             the only real-time GI in Godot that needs no author-time step.
##  SSR        wet asphalt is a signature look here (sky_weather runs a 105 s
##             dry-down); a wet road with no reflection is a grey road.
##  VOL FOG    sun shafts down the avenues at dusk, and 492 suburb OmniLights
##             become visible cones for free (light_volumetric_fog_energy = 1).
##  SHADOWS    4 hand-split cascades to 900 m — D-025 says the aerial view is
##             flat, and it is, because nothing casts past 300 m.
##  GRADE      a generated 32^3 filmic LUT + contrast/saturation. Post-tonemap,
##             so it CANNOT move anything relative to glow_hdr_threshold.
##  EXPOSURE   a deterministic time-of-day ramp, NOT auto exposure. See below.
##
## ── THE TWO THINGS DELIBERATELY NOT SHIPPED ──────────────────────────────────
##  1. AUTO EXPOSURE. Every quality number in docs/qa/defects.md is screenshot
##     photometry, and `zz_shot.gd::_settle_and_save` gives a plate 8 process
##     frames. `CameraAttributesPractical.auto_exposure_speed` converges over
##     ~1/speed SECONDS, so plates would be captured mid-adaptation and the
##     ledger's photometric history would stop being comparable to itself. It is
##     built and reachable behind `--env-autoexposure` for anyone who wants to
##     price it; the shipped path is `EXPOSURE_*` below, which is a pure
##     function of time of day and therefore reproducible.
##  2. PhysicalSkyMaterial. `sky_weather.gd` retires the ProceduralSkyMaterial
##     on frame 0 and installs a custom dome that already has cloud decks, a
##     swelling sun disc, a moon with a terminator, a star field with a Milky
##     Way band and two haze layers. PhysicalSky has none of that and goes black
##     at night. The Rayleigh/Mie upgrade went INSIDE the existing dome instead.
##
## Zero asset files, per project doctrine: the LUT is generated in code.

# ============================== SDFGI ========================================
# The map spans roughly x[-712, 880] z[-520, 1000] with towers to ~150 m.
# Cascade 0 must cover a downtown block; the last cascade should reach about as
# far as the shadow cascades usefully resolve. min_cell_size 0.5 m gives
# cascade0 = 0.5 * 64 = 32 m and 4 cascades = 32 * 8 = 256 m of GI.
# A 0.5 m cell CANNOT represent a 0.2 m wall — that is the leak budget, stated
# up front rather than discovered in a screenshot.
const SDFGI_CASCADES := 4
const SDFGI_MIN_CELL := 0.5          # m -> cascade0 32 m, range 256 m
const SDFGI_BOUNCE := 0.5            # >0.5 runs away on sunlit concrete
const SDFGI_ENERGY := 1.0
const SDFGI_NORMAL_BIAS := 1.1
const SDFGI_PROBE_BIAS := 1.1
# Y_SCALE_75 is the engine default and the right one here: the sprawl is flat
# but the towers are not, and 50% would smear floor-to-floor.
#
# CONVERGENCE — MEASURED, and the measurement changed the answer. More frames of
# accumulation = a quieter image but a slower settle after a camera teleport.
# Two independent boots photographed at the SAME depth (309 frames after the
# teleport), downtown_day, mean Rec.709 luminance of the whole frame:
#     no SDFGI          0.38 % of pixels differ, mean luminance -0.01  (control)
#     SDFGI converge=10 6.85 % differ,           mean luminance -1.77
#     SDFGI converge=30 4.36 % differ,           mean luminance +1.13
# The control proves the rest of the scene is deterministic (seeded traffic), so
# that residual is SDFGI and nothing else. 30 was chosen for the quieter number:
# every quality figure in docs/qa/defects.md is plate photometry, and a GI
# solution that makes two identical boots disagree by 2 luminance units is a
# permanent tax on the project's own measuring instrument. See the artefact
# section of docs/tech/rendering/light-pipeline.md.
const SDFGI_CONVERGE_FRAMES := 30
const SDFGI_LIGHT_FRAMES := 2        # the sun moves 24 h in 600 s here
# What a camera teleport costs before a plate is trustworthy, MEASURED at
# downtown_day against a 309-frame plate: 10 frames is -5.21 luminance short,
# 30 is -4.66 short, 60 is within -2.17 (and -2.17 is about the size of the
# flicker floor above, so 60 is where settle stops being the limiting term).
# `zz_shot.gd::_settle_and_save` currently awaits EIGHT. Reported, not fixed:
# zz_shot is not this mission's file.
const SETTLE_FRAMES := 60

# SDFGI double-counts with sky ambient: both are "light arriving from the
# environment". sky_weather scales `ambient_light_energy` by this when SDFGI is
# live. It is NOT flat, because SDFGI's night contribution is nearly nothing
# (it reads a night sky) while its day contribution is large — so day gives way
# and night keeps what it had. This is the D-079 lever.
const SDFGI_AMBIENT_DAY := 0.58
const SDFGI_AMBIENT_NIGHT := 0.96

# ============================== SSR ==========================================
# 32 steps not 64: at 1600x900 the extra 32 buy reflection length on surfaces
# that are, in this game, almost all rough. fade_in keeps the reflection off the
# contact point (where SSR has no data and smears); fade_out ends it before the
# screen edge so a reflection never pops when the camera turns.
const SSR_MAX_STEPS := 32
const SSR_FADE_IN := 0.15
const SSR_FADE_OUT := 2.0
const SSR_DEPTH_TOLERANCE := 0.2

# ============================== VOLUMETRIC FOG ===============================
# Defaults only; sky_weather owns density/albedo/emission per time of day (that
# is why it owns this feature at all). LENGTH is how far the froxel volume
# reaches — 128 m puts the far end past the avenue, and past the point where
# `fog_density`'s exponential haze takes over anyway.
const VFOG_LENGTH := 128.0
const VFOG_DETAIL_SPREAD := 2.0
const VFOG_ANISOTROPY := 0.45        # forward scattering = the shaft toward sun
const VFOG_GI_INJECT := 1.0          # SDFGI lights the air, not just surfaces
const VFOG_AMBIENT_INJECT := 0.25
# The dome is a hand-authored shader with canon colours in it. Letting volume
# fog repaint the sky would do to it exactly what `fog_sky_affect = 1.0` did in
# M8 (the whole dome read as tan haze at noon).
const VFOG_SKY_AFFECT := 0.0
const VFOG_VOLUME := 96              # froxel grid X/Y (engine default 64)
const VFOG_DEPTH := 96               # froxel grid Z   (engine default 64)

# ============================== SHADOWS (D-025) ==============================
# `aerial` shoots from (880,300,880) at (300,0,230) — 921 m. At 300 m the whole
# frame is shadowless and 108 towers of varied height look like a printed map.
# 900 m covers it. The splits are hand-set and front-loaded: cascade 0 holds the
# 36 m the player is actually standing in, and the last cascade eats the rest.
const SHADOW_MAX_DISTANCE := 900.0
const SHADOW_SPLIT_1 := 0.04         # ->  36 m   street, cars, people
const SHADOW_SPLIT_2 := 0.12         # -> 108 m   the block
const SHADOW_SPLIT_3 := 0.33         # -> 297 m   the district (old whole range)
const SHADOW_FADE_START := 0.92      # the last 8% dissolves instead of clipping
const SHADOW_BLEND_SPLITS := true    # no visible cascade seam across a street
# PCSS-style contact hardening. 0.53 deg is the sun's real angular diameter;
# this is the single number that stops every shadow in the game having the same
# razor edge whether it is a kerb or a 150 m tower.
const SUN_ANGULAR_DISTANCE := 0.53
const SUN_SHADOW_BLUR := 1.0
const SUN_SHADOW_BIAS := 0.04
const SUN_SHADOW_NORMAL_BIAS := 1.4  # up from 1.0: a 900 m cascade needs it
const SUN_PANCAKE := 20.0
const SHADOW_ATLAS := 8192           # 16-bit -> 128 MB. 4096 is the fallback.
const SHADOW_ATLAS_16BIT := true
# ---- BUDGET TIER (`--env-budget`, D-040). The full set measured 17.5-25 ms at every
# perf station on a quiet machine; the bar is 16.67. Ablation (meas7/ablation.md):
# SDFGI ~6 ms, TAA ~1.4, volfog ~1.3, SSR ~0.6, and the 8192 atlas + Soft High filter
# were never ablated. This tier keeps every feature ON and cuts the resolution of
# each: fewer/larger GI cascades with 16 rays and an 8-frame light update, a 64^3
# froxel grid, 16 SSR steps, a 4096 atlas at Soft Medium over 600 m with the same
# 36/108/300 m near cascades. It is a candidate default, not a downgrade switch.
const SDFGI_CASCADES_BUDGET := 3
const SDFGI_MIN_CELL_BUDGET := 0.75  # cascade0 48 m, range 192 m
const SSR_MAX_STEPS_BUDGET := 12
const VFOG_VOLUME_BUDGET := 48       # first budget cut (64) left hospital_door_night at 18.06 ms
const SHADOW_ATLAS_BUDGET := 4096
const SHADOW_MAX_DISTANCE_BUDGET := 450.0   # hospital_door looks down the whole of downtown;
                                            # at 600 m its far cascade re-rendered every tower
const SHADOW_SPLIT_1_BUDGET := 0.08  # ->  36 m (same street cascade as the full tier)
const SHADOW_SPLIT_2_BUDGET := 0.24  # -> 108 m
const SHADOW_SPLIT_3_BUDGET := 0.60  # -> 270 m
const SDFGI_LIGHT_FRAMES_BUDGET := 16   # the sun moves 0.16 deg per update at this rate
const POSITIONAL_ATLAS := 4096

# ============================== EXPOSURE / GRADE =============================
# Deterministic exposure ramp keyed to sun elevation, in stops. Negative = stop
# down. Noon stops down (a Texas noon is genuinely brighter than the display can
# show, and ACES was clipping it); night opens up so it is dark but readable.
const EXPOSURE_NOON_STOPS := -0.20   # M23: -0.35 read underexposed vs legacy at street_north/sky_wide
const EXPOSURE_DUSK_STOPS := 0.10
const EXPOSURE_NIGHT_STOPS := 0.55
const ADJUST_CONTRAST := 1.06
const ADJUST_SATURATION := 1.08
const ADJUST_BRIGHTNESS := 1.0
const LUT_SIZE := 32
# The grade, as three numbers somebody can argue with. Shadows go cool (a
# daylight-balanced camera renders shade blue because it IS blue — it is lit by
# sky, not sun), highlights go warm, and the toe lifts a hair so black is
# charcoal rather than a hole.
const LUT_SHADOW_TINT := Color(0.94, 0.98, 1.06)
const LUT_HIGHLIGHT_TINT := Color(1.045, 1.005, 0.955)
const LUT_TOE_LIFT := 0.008
const LUT_SHOULDER := 0.94           # <1 rolls the top off before pure white

# Auto exposure, only reachable via `--env-autoexposure`. See the header.
const AE_MIN_SENSITIVITY := 40.0
const AE_MAX_SENSITIVITY := 1600.0
const AE_SPEED := 2.5
const AE_SCALE := 0.42

# ============================== ANTI-ALIASING ================================
# Decided with a number; see docs/tech/rendering/light-pipeline.md. MSAA does
# nothing for SDFGI/SSR specular shimmer — it is a geometry-edge tool — and the
# shimmer is what this pass introduced, so TAA carries the load and MSAA drops
# from 8x to 2x to pay for it.
const AA_MSAA := Viewport.MSAA_2X
const AA_TAA := true
const AA_FXAA := false

# Legacy (= the tree as it stood before this pass) GPU-side state.
const LEGACY_MSAA := Viewport.MSAA_8X
const LEGACY_SHADOW_ATLAS := 4096
const LEGACY_SOFT_FILTER := 2        # engine default "Soft Low"
const LEGACY_POSITIONAL_ATLAS := 4096
const LEGACY_VFOG_VOLUME := 64

# ============================== FLAGS ========================================
static var _flags: Dictionary = {}
static var _parsed := false
static var _lut: ImageTexture3D = null


## Parsed once, cached. Every key is a bool; absent means false.
static func flags() -> Dictionary:
	if _parsed:
		return _flags
	_parsed = true
	var a := OS.get_cmdline_user_args()
	_flags = {
		"legacy": a.has("--env-legacy"),
		"no_sdfgi": a.has("--env-no-sdfgi"),
		"no_ssr": a.has("--env-no-ssr"),
		"no_volfog": a.has("--env-no-volfog"),
		"no_taa": a.has("--env-no-taa"),
		"no_shadows": a.has("--env-no-farshadow"),
		"no_grade": a.has("--env-no-grade"),
		"no_scatter": a.has("--env-no-scatter"),
		"no_exposure": a.has("--env-no-exposure"),
		"autoexposure": a.has("--env-autoexposure"),
		"ssil": a.has("--env-ssil"),
		# D-040/D-042: the BUDGET tier is the shipped default (10/10 stations ≤16.67 ms
		# with TAA-only AA); the full "photo" set is opt-in and fails the bar at every
		# station on the dev machine. `--env-budget` is accepted for old scripts.
		"budget": not a.has("--env-photo"),
	}
	return _flags


## The one question the rest of the project asks this file. `sky_weather` uses
## it to decide whether to drive volumetric fog and whether to scale ambient
## against SDFGI; nothing else should need it.
static func on(feature: String) -> bool:
	var f := flags()
	if f["legacy"]:
		return false
	match feature:
		"sdfgi": return not f["no_sdfgi"]
		"ssr": return not f["no_ssr"]
		"volfog": return not f["no_volfog"]
		"grade": return not f["no_grade"]
		"scatter": return not f["no_scatter"]
		"exposure": return not f["no_exposure"]
		"farshadow": return not f["no_shadows"]
	return false


# ============================== BUILD ========================================
## Builds the WorldEnvironment and the sun, parents them to `host`, prints the
## D-032 census line, and hands both back. The caller keeps the handles because
## `sky_weather` reads them off main by name.
## True under `--env-budget`: every feature on, each at its cheaper resolution.
static func budget() -> bool:
	return bool(flags().get("budget", false))


static func build(host: Node3D) -> Dictionary:
	var f := flags()
	var env := _base_environment()
	var sun := _base_sun()
	if f["legacy"]:
		_apply_gpu_state(host, true)
		_census("legacy", "off", "off", _aa_name(LEGACY_MSAA, false), "custom(m16)")
	else:
		_apply_features(env, sun)
		_apply_gpu_state(host, false)
		var b := budget()
		_census(
			"on c%d cell%.2f r%d l%d" % [
				SDFGI_CASCADES_BUDGET if b else SDFGI_CASCADES,
				SDFGI_MIN_CELL_BUDGET if b else SDFGI_MIN_CELL,
				16 if b else 64, SDFGI_LIGHT_FRAMES_BUDGET if b else 2] if on("sdfgi") else "off",
			"on s%d" % (SSR_MAX_STEPS_BUDGET if b else SSR_MAX_STEPS) if on("ssr") else "off",
			"on %dx%d" % ([VFOG_VOLUME_BUDGET, VFOG_VOLUME_BUDGET] if b else [VFOG_VOLUME, VFOG_DEPTH]) if on("volfog") else "off",
			_aa_name(int(_aa_choice()[0]),
				bool(_aa_choice()[1]) and not f["no_taa"]),
			"custom(m16)+scatter" if on("scatter") else "custom(m16)")
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	if not f["legacy"]:
		we.camera_attributes = _camera_attributes()
	host.add_child(we)
	host.add_child(sun)
	return {"world_env": we, "sun": sun}


## EXACTLY the pre-M23 environment. Every line below existed in
## `main.gd::_build_environment` before this pass and is reproduced verbatim so
## `--env-legacy` is a true arm A. Do not "clean this up".
static func _base_environment() -> Environment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.42, 0.66)
	sky_mat.sky_horizon_color = Color(0.86, 0.71, 0.52)
	sky_mat.ground_bottom_color = Color(0.2, 0.17, 0.13)
	sky_mat.ground_horizon_color = Color(0.86, 0.71, 0.52)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.81, 0.88)  # boot value; sky_weather drives it per tick
	env.fog_density = 0.0004
	# Default sky_affect (1.0) repaints the ENTIRE sky in fog color — the whole
	# dome read as tan haze at noon (M8 screenshot review). Keep a whisper of
	# horizon haze; let the sky material actually show.
	env.fog_sky_affect = 0.1
	# M12 graphics pass. ACES filmic curve stops daylight clipping to white and
	# gives night its contrast; glow is HDR-thresholded so ONLY emissives bloom
	# (lit windows, signals, neon, the Green Light) and painted surfaces never
	# haze; SSAO grounds the boxes. glow_hdr_threshold 1.05 is a PROJECT-WIDE
	# CONTRACT (D-032 re-tuned 827 strip lights and 22 tower collars to it) and
	# is not touched by this pass — the grade is post-tonemap for exactly that
	# reason.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	return env


static func _base_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38, 42, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	return sun


# ============================== THE NEW LAYERS ===============================
static func _apply_features(env: Environment, sun: DirectionalLight3D) -> void:
	var f := flags()

	# ---- GLOBAL ILLUMINATION -------------------------------------------------
	if on("sdfgi"):
		env.sdfgi_enabled = true
		env.sdfgi_cascades = SDFGI_CASCADES_BUDGET if budget() else SDFGI_CASCADES
		env.sdfgi_min_cell_size = SDFGI_MIN_CELL_BUDGET if budget() else SDFGI_MIN_CELL
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = SDFGI_BOUNCE
		env.sdfgi_energy = SDFGI_ENERGY
		env.sdfgi_normal_bias = SDFGI_NORMAL_BIAS
		env.sdfgi_probe_bias = SDFGI_PROBE_BIAS
		env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT

	# ---- REFLECTIONS ---------------------------------------------------------
	if on("ssr"):
		env.ssr_enabled = true
		env.ssr_max_steps = SSR_MAX_STEPS_BUDGET if budget() else SSR_MAX_STEPS
		env.ssr_fade_in = SSR_FADE_IN
		env.ssr_fade_out = SSR_FADE_OUT
		env.ssr_depth_tolerance = SSR_DEPTH_TOLERANCE

	# ---- SCREEN-SPACE INDIRECT (opt-in probe only) ---------------------------
	if f["ssil"]:
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.ssil_intensity = 1.0
		env.ssil_sharpness = 0.98
		env.ssil_normal_rejection = 1.0

	# ---- VOLUMETRIC FOG ------------------------------------------------------
	# Enabled here with safe defaults; sky_weather writes density/albedo/
	# emission every physics tick from the time of day and the storm mix.
	if on("volfog"):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.008
		env.volumetric_fog_albedo = Color(0.86, 0.87, 0.90)
		env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_length = VFOG_LENGTH
		env.volumetric_fog_detail_spread = VFOG_DETAIL_SPREAD
		env.volumetric_fog_anisotropy = VFOG_ANISOTROPY
		env.volumetric_fog_gi_inject = VFOG_GI_INJECT if on("sdfgi") else 0.0
		env.volumetric_fog_ambient_inject = VFOG_AMBIENT_INJECT
		if "volumetric_fog_sky_affect" in env:
			env.volumetric_fog_sky_affect = VFOG_SKY_AFFECT

	# ---- COLOUR GRADE (post-tonemap: cannot move the glow threshold) ---------
	if on("grade"):
		env.adjustment_enabled = true
		env.adjustment_brightness = ADJUST_BRIGHTNESS
		env.adjustment_contrast = ADJUST_CONTRAST
		env.adjustment_saturation = ADJUST_SATURATION
		env.adjustment_color_correction = lut()

	# ---- SHADOWS (D-025) -----------------------------------------------------
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE
	sun.shadow_bias = SUN_SHADOW_BIAS
	sun.shadow_normal_bias = SUN_SHADOW_NORMAL_BIAS
	if "shadow_blur" in sun:
		sun.shadow_blur = SUN_SHADOW_BLUR
	sun.directional_shadow_pancake_size = SUN_PANCAKE
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = SHADOW_BLEND_SPLITS
	sun.directional_shadow_split_1 = SHADOW_SPLIT_1_BUDGET if budget() else SHADOW_SPLIT_1
	sun.directional_shadow_split_2 = SHADOW_SPLIT_2_BUDGET if budget() else SHADOW_SPLIT_2
	sun.directional_shadow_split_3 = SHADOW_SPLIT_3_BUDGET if budget() else SHADOW_SPLIT_3
	sun.directional_shadow_fade_start = SHADOW_FADE_START
	if on("farshadow"):
		sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE_BUDGET if budget() else SHADOW_MAX_DISTANCE


## GPU-side state that does not live on the Environment resource. Applied to the
## root viewport and the RenderingServer so `--env-legacy` can restore it
## regardless of what `[rendering]` in project.godot says.
static func _apply_gpu_state(host: Node, legacy: bool) -> void:
	var vp := host.get_viewport()
	if vp != null:
		if legacy:
			vp.msaa_3d = LEGACY_MSAA
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.positional_shadow_atlas_size = LEGACY_POSITIONAL_ATLAS
		else:
			# `--env-aa=off|msaa2|msaa4|msaa8|taa|msaa2taa|msaa8taa` prices the
			# anti-aliasing choice from one tree. MSAA is a geometry-edge tool;
			# the shimmer SDFGI and SSR introduce is specular, which only a
			# temporal filter can touch — so this flag is how that claim was
			# turned into a number instead of an opinion.
			var aa := _aa_choice()
			vp.msaa_3d = aa[0]
			vp.use_taa = aa[1] and not flags()["no_taa"]
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if AA_FXAA \
				else Viewport.SCREEN_SPACE_AA_DISABLED
			vp.positional_shadow_atlas_size = POSITIONAL_ATLAS
	var rs := RenderingServer
	if legacy:
		rs.directional_shadow_atlas_set_size(LEGACY_SHADOW_ATLAS, true)
		rs.directional_soft_shadow_filter_set_quality(LEGACY_SOFT_FILTER)
		rs.positional_soft_shadow_filter_set_quality(LEGACY_SOFT_FILTER)
		rs.environment_set_volumetric_fog_volume_size(
			LEGACY_VFOG_VOLUME, LEGACY_VFOG_VOLUME)
		return
	rs.directional_shadow_atlas_set_size(
		SHADOW_ATLAS_BUDGET if budget() else SHADOW_ATLAS, SHADOW_ATLAS_16BIT)
	# PCSS needs a real filter to sample with; "Soft High" is what makes
	# light_angular_distance read as a penumbra instead of a jitter. The budget
	# tier steps each filter down one notch.
	rs.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if budget()
		else RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	rs.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if budget()
		else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	if on("volfog"):
		var fv := VFOG_VOLUME_BUDGET if budget() else VFOG_VOLUME
		rs.environment_set_volumetric_fog_volume_size(fv, VFOG_VOLUME_BUDGET if budget() else VFOG_DEPTH)
		rs.environment_set_volumetric_fog_filter_active(true)
	if on("sdfgi"):
		rs.environment_set_sdfgi_frames_to_converge(_converge_enum())
		rs.environment_set_sdfgi_frames_to_update_light(
			RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_16_FRAMES if budget()
			else RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES)
		rs.environment_set_sdfgi_ray_count(
			RenderingServer.ENV_SDFGI_RAY_COUNT_16 if budget()
			else RenderingServer.ENV_SDFGI_RAY_COUNT_64)


## How many frames SDFGI accumulates over. MORE frames = more temporal
## averaging = a QUIETER image but a slower settle after a camera teleport.
## `--env-sdfgi-converge=N` (N in 5/10/15/20/25/30) exists because that trade is
## the single most consequential SDFGI knob in this project: every quality
## number in the defect ledger is plate photometry, and a noisy GI solution
## makes two identical boots disagree.
## [msaa enum, taa] for the current `--env-aa=` choice, defaulting to the
## shipped pair. Kept as data so the census line and the viewport can never
## disagree about which arm is running.
static func _aa_choice() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env-aa="):
			match a.get_slice("=", 1):
				"off": return [Viewport.MSAA_DISABLED, false]
				"msaa2": return [Viewport.MSAA_2X, false]
				"msaa4": return [Viewport.MSAA_4X, false]
				"msaa8": return [Viewport.MSAA_8X, false]
				"taa": return [Viewport.MSAA_DISABLED, true]
				"msaa2taa": return [Viewport.MSAA_2X, true]
				"msaa8taa": return [Viewport.MSAA_8X, true]
	# Budget tier: TAA alone. MSAA 2x under TAA was redundant and cost the night
	# respawn frame its whole margin (D-042).
	if budget():
		return [Viewport.MSAA_DISABLED, true]
	return [AA_MSAA, AA_TAA]


static func _converge_enum() -> int:
	var want := SDFGI_CONVERGE_FRAMES
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env-sdfgi-converge="):
			want = int(a.get_slice("=", 1))
	match want:
		5: return RenderingServer.ENV_SDFGI_CONVERGE_IN_5_FRAMES
		15: return RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES
		20: return RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES
		25: return RenderingServer.ENV_SDFGI_CONVERGE_IN_25_FRAMES
		30: return RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES
	return RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES


# ============================== EXPOSURE =====================================
static func _camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	if flags()["autoexposure"]:
		ca.auto_exposure_enabled = true
		ca.auto_exposure_min_sensitivity = AE_MIN_SENSITIVITY
		ca.auto_exposure_max_sensitivity = AE_MAX_SENSITIVITY
		ca.auto_exposure_speed = AE_SPEED
		ca.auto_exposure_scale = AE_SCALE
	else:
		ca.auto_exposure_enabled = false
	ca.exposure_multiplier = 1.0      # sky_weather writes the ToD ramp here
	return ca


## Stops -> linear multiplier. Public so sky_weather's ramp is one call and the
## unit ("stops") is not lost in a magic number.
static func stops(s: float) -> float:
	return pow(2.0, s)


# ============================== THE LUT ======================================
## A 32^3 filmic grade, generated once. Cool shade, warm highlight, a lifted toe
## and a rolled shoulder. `adjustment_color_correction` is applied AFTER the
## tonemapper, which is the whole reason the grade lives here and not in the
## exposure: it cannot change what crosses glow_hdr_threshold = 1.05.
static func lut() -> ImageTexture3D:
	if _lut != null:
		return _lut
	var slices: Array[Image] = []
	var n := float(LUT_SIZE - 1)
	for b in LUT_SIZE:
		var img := Image.create(LUT_SIZE, LUT_SIZE, false, Image.FORMAT_RGB8)
		for g in LUT_SIZE:
			for r in LUT_SIZE:
				var c := Vector3(float(r) / n, float(g) / n, float(b) / n)
				img.set_pixel(r, g, _grade(c))
		slices.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, slices)
	_lut = t
	return _lut


static func _grade(c: Vector3) -> Color:
	# Luma decides how much of the shadow tint vs the highlight tint a colour
	# gets, so the grade is a split-tone and not a global cast.
	var l := c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
	var w := smoothstep(0.12, 0.78, l)
	var tint := Vector3(
		lerpf(LUT_SHADOW_TINT.r, LUT_HIGHLIGHT_TINT.r, w),
		lerpf(LUT_SHADOW_TINT.g, LUT_HIGHLIGHT_TINT.g, w),
		lerpf(LUT_SHADOW_TINT.b, LUT_HIGHLIGHT_TINT.b, w))
	var o := Vector3(c.x * tint.x, c.y * tint.y, c.z * tint.z)
	# Toe lift, then a shoulder that stops the top of the range going flat white
	# before the display does.
	o = Vector3(_curve(o.x), _curve(o.y), _curve(o.z))
	return Color(clampf(o.x, 0.0, 1.0), clampf(o.y, 0.0, 1.0), clampf(o.z, 0.0, 1.0))


static func _curve(v: float) -> float:
	var x := clampf(v, 0.0, 1.0)
	x = LUT_TOE_LIFT + x * (1.0 - LUT_TOE_LIFT)
	# A gentle shoulder: pull the top toward LUT_SHOULDER * 1.0 without
	# clipping, so specular highlights keep their hue instead of blowing white.
	return x - (1.0 - LUT_SHOULDER) * x * x * x


# ============================== CENSUS =======================================
static func _aa_name(msaa: int, taa: bool) -> String:
	var m := "off"
	match msaa:
		Viewport.MSAA_2X: m = "msaa2x"
		Viewport.MSAA_4X: m = "msaa4x"
		Viewport.MSAA_8X: m = "msaa8x"
	return m + ("+taa" if taa else "")


static func _census(sdfgi: String, ssr: String, volfog: String, aa: String,
		sky: String) -> void:
	print("RENDER: tier=%s sdfgi=%s ssr=%s volfog=%s aa=%s sky=%s shadow=%dm/%s grade=%s exposure=%s" % [
		"legacy" if flags()["legacy"] else ("budget" if budget() else "photo"),
		sdfgi, ssr, volfog, aa, sky,
		(int(SHADOW_MAX_DISTANCE_BUDGET) if budget() else int(SHADOW_MAX_DISTANCE)) if on("farshadow") else 300,
		"pcss%.2fdeg" % SUN_ANGULAR_DISTANCE if not flags()["legacy"] else "hard",
		"lut%d" % LUT_SIZE if on("grade") else "off",
		"auto" if flags()["autoexposure"] else ("tod" if not flags()["legacy"] else "off")])
