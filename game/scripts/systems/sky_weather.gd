extends Node
## SKY + WEATHER v1 — day/night cycle plus the supercell weather machine.
## Owns main.sun and main.world_env from here on: sun rotation/energy/colour,
## ProceduralSkyMaterial colours, ambient energy, and fog. The sky is Dorado's
## terrain and boss fight: a 600 s day with an enormous flat-horizon Texas
## sunset, then a seeded CLEAR -> BUILDING -> STORM -> CLEARING supercell with
## player-following rain, lightning + synthesized thunder, wind gusts, wet
## roads (grip 0.72 on every RaycastVehicle), and — this is Texas — a tornado
## siren on a quarter of storms. ENTIRELY INERT in smoke mode: setup returns
## before touching anything, so the smoke environment stays byte-identical.
## If either world handle is missing, the system no-ops forever.

enum WState { CLEAR, BUILDING, STORM, CLEARING }

# ============================== TUNABLES =====================================
const RNG_SEED := 20260730; const MIX_RATE := 22050  # seed; Hz, both buffers

# Day/night. Elevation is sinusoidal, peaking MAX_ELEV_DEG at NOON_HOUR
# (sunrise/sunset 07:30 / 19:30); azimuth sweeps 15 deg per game hour.
const DAY_LENGTH := 600.0; const START_HOUR := 9.5   # s per 24 h; boot 09:30
const NOON_HOUR := 13.5; const MAX_ELEV_DEG := 65.0  # solar noon; peak elev
const SUNSET_WARM_ELEV := 15.0       # below this the light warms and reddens
const NIGHT_FADE_ELEV := -6.0        # dusk finishes fading by this elevation
const SKY_DAY_ELEV := 25.0           # sky colours fully "day" above this
const MIN_APPLIED_ELEV := 3.0        # never graze the horizon (shadow acne)
const AZIMUTH_DEG_PER_HOUR := 15.0
const NOON_SUN_ENERGY := 1.35; const WARM_SUN_ENERGY := 0.9; const HORIZON_SUN_ENERGY := 0.3
const NIGHT_SUN_ENERGY := 0.06       # cool-blue moonlight stand-in
const DAY_AMBIENT := 1.0; const NIGHT_AMBIENT := 0.28

# Sky / sun / fog keyframes (DAY_* match main.gd's boot values).
const DAY_TOP := Color(0.25, 0.42, 0.66); const DAY_HOR := Color(0.72, 0.79, 0.88)  # M23: was tan (0.86,0.71,0.52) — read as a sandstorm from `aerial`
const DAWN_TOP := Color(0.36, 0.38, 0.58); const DAWN_HOR := Color(0.98, 0.62, 0.40)
const DUSK_TOP := Color(0.30, 0.24, 0.46)
const DUSK_HOR := Color(1.0, 0.47, 0.22)  # flat-horizon money shot
const NIGHT_TOP := Color(0.015, 0.025, 0.07); const NIGHT_HOR := Color(0.06, 0.08, 0.15)
const DAY_SUN := Color(1.0, 0.95, 0.85); const SUNSET_SUN := Color(1.0, 0.42, 0.20)
const NIGHT_SUN := Color(0.55, 0.66, 1.0)
const DAY_GROUND := Color(0.2, 0.17, 0.13); const NIGHT_GROUND := Color(0.02, 0.02, 0.035)
const DAY_FOG := Color(0.76, 0.81, 0.88); const NIGHT_FOG := Color(0.10, 0.12, 0.20)  # M23: daylight haze is blue-white, not tan
const DAY_FOG_DENSITY := 0.0002; const NIGHT_FOG_DENSITY := 0.0009  # M23: day was 0.0004 — `aerial` lost a third of the city at 1 km

# Supercell overlay, blended by _mix (0 = fair weather, 1 = full storm).
const STORM_TOP := Color(0.16, 0.19, 0.18)
const STORM_HOR := Color(0.34, 0.44, 0.36)   # supercell green is canon
const STORM_SUN_FACTOR := 0.35       # storm darkens the sun to ~35%
const STORM_SUN := Color(0.72, 0.76, 0.72); const STORM_GROUND := Color(0.09, 0.10, 0.09)
const STORM_FOG := Color(0.45, 0.50, 0.47); const STORM_FOG_DENSITY := 0.0030
const STORM_AMBIENT_FACTOR := 0.55

# Weather machine timings (all rolls seeded).
const CLEAR_RANGE := Vector2(120.0, 300.0); const BUILDING_SECONDS := 45.0
const STORM_RANGE := Vector2(60.0, 150.0); const CLEARING_SECONDS := 30.0
const BUILD_MIX := 0.5               # end-of-BUILDING mix: sky ~30% darker
const STORM_RAMP_SECONDS := 8.0      # mix BUILD_MIX -> 1.0 inside STORM

# Rain: ONE GPU box that follows the player, built lazily at first storm.
const RAIN_AMOUNT := 2000            # allocated once; ramped via amount_ratio
const RAIN_BOX := Vector3(44.0, 30.0, 44.0); const RAIN_HEIGHT := 14.0
const RAIN_LIFETIME := 1.3; const RAIN_GRAVITY := -26.0
const RAIN_SPEED_MIN := 16.0; const RAIN_SPEED_MAX := 24.0
const RAIN_WIND_TILT := 0.18         # sideways lean of the fall direction
const RAIN_STREAK := Vector3(0.02, 0.5, 0.02)  # tiny elongated streak mesh
const RAIN_COLOR := Color(0.72, 0.78, 0.9, 0.5)

# Lightning + thunder.
const STRIKE_RANGE := Vector2(4.0, 12.0)   # s between strikes
const FLASH_SECONDS := 0.1; const FLASH_SUN_MULT := 3.0; const FLASH_AMBIENT_ADD := 1.4
const THUNDER_RANGE := Vector2(1.5, 4.0); const THUNDER_SECONDS := 2.5  # delay (s); buffer len
const THUNDER_NEAR_DB := -4.0        # short delay = close strike = loud
const THUNDER_FAR_DB := -16.0

# Wind gusts (300-900 N sinusoidal, seeded per-storm direction) + wet roads.
const WIND_RADIUS := 100.0; const WIND_GUST_HZ := 0.35
const WIND_MIN_N := 300.0; const WIND_MAX_N := 900.0
const WET_GRIP := 0.72; const DRY_GRIP := 1.0
# M22 wet LOOK. Asphalt soaks fast and dries slow; a storm runs 60-150 s and
# CLEARING another 30, so a 105 s dry-down means the street is still visibly
# damp and reflective well after the rain quits — which is what it does.
const WET_SOAK_SECONDS := 14.0; const WET_DRY_SECONDS := 105.0

# Tornado siren.
const SIREN_CHANCE := 0.25; const SIREN_PLAY_SECONDS := 25.0
const SIREN_LOOP_SECONDS := 10.0     # one slow rise-fall wail per loop
const SIREN_DB := -18.0              # quiet-ish, unsettling
const SIREN_LOW_HZ := 400.0; const SIREN_HIGH_HZ := 800.0
const SIREN_PEAK_MIX := 0.98         # "storm peak": fire once fully ramped

# ===================== M16 SCENIC SKY (VISUAL ONLY) ==========================
# The sky stopped being a two-colour gradient. A custom sky shader owns the
# dome now: a projected cumulus deck with real perspective, a sun disc that
# swells and reddens on the way down, a moon with maria and a terminator, a
# star field with a Milky Way band, and two layers of horizon haze. Every
# value below is a LOOK constant. The weather machine, its timings, its grip
# values and its seeded stream are untouched — this layer only reads _mix,
# _flash_t, _wind_dir and the sun elevation the machine already computed.
const TEX := preload("res://scripts/world/city_textures.gd")
const SHADERS := preload("res://scripts/world/city_shaders.gd")
const RENDER := preload("res://scripts/world/render_pipeline.gd")

# ============ M23 LIGHT PIPELINE — what this system drives on top ============
# render_pipeline.gd BUILDS the rig (SDFGI, SSR, volumetric fog, the cascade
# rig, the LUT). This system drives everything about it that CHANGES with the
# clock and the storm, because the clock and the storm are already here.
#
# VOLUMETRIC FOG. Density is a time-of-day curve, not a constant: at noon a dry
# North Texas sky has almost nothing in it, at dusk the air is full of it and
# that is what makes a sun shaft down an avenue, overnight it settles again, and
# a supercell fills the air completely. STORM_VFOG is deliberately ~6x the noon
# value — under a shelf cloud you should not be able to see the far end of
# downtown.
const VFOG_NOON := 0.0055; const VFOG_DUSK := 0.0230
const VFOG_NIGHT := 0.0120; const VFOG_STORM := 0.0340
# Dusk window, in sun-elevation degrees: the shaft hour. Peaks where the sun is
# low enough to rake through the towers but still bright enough to carry.
const VFOG_DUSK_ELEV := 14.0; const VFOG_DUSK_WIDTH := 22.0
# Albedo is what colour the AIR is. Day air is neutral-cool, dusk air takes the
# sun, night air takes the sodium/mercury wash the city is throwing up at it,
# storm air is the green-grey of the canon supercell.
const VFOG_ALBEDO_DAY := Color(0.88, 0.90, 0.95)
const VFOG_ALBEDO_DUSK := Color(1.00, 0.82, 0.66)
const VFOG_ALBEDO_NIGHT := Color(0.62, 0.66, 0.82)
const VFOG_ALBEDO_STORM := Color(0.66, 0.72, 0.68)
# A whisper of self-emission at night ONLY. This is the city's own light dome —
# the thing that makes a distant skyline sit in a bowl of glow instead of a
# black hole. Zero by day or it fogs the whole map.
const VFOG_EMIT_NIGHT := Color(0.10, 0.12, 0.19); const VFOG_EMIT_ENERGY := 0.22
# Anisotropy: forward scattering. Higher = a tighter, brighter shaft toward the
# sun. Storms scatter more isotropically (the light is coming from everywhere).
const VFOG_ANISO_CLEAR := 0.55; const VFOG_ANISO_STORM := 0.10

# EXPOSURE. A deterministic ramp in stops, keyed to sun elevation. NOT auto
# exposure — see the header of render_pipeline.gd for why that would break the
# defect ledger's photometry. Reproducible: the same time_of_day always gives
# the same exposure, so a plate taken today is comparable to a plate from
# cycle 2.
const EXP_NOON := -0.35; const EXP_DUSK := 0.10; const EXP_NIGHT := 0.55
const EXP_STORM := 0.28              # a supercell steals ~1/3 stop of daylight

# SDFGI vs SKY AMBIENT. Both are "light arriving from the environment", so with
# SDFGI on, `ambient_light_energy` has to give way or the world double-counts
# and noon goes milky. It gives way by DAY (where SDFGI's bounce is strong) and
# barely at all at NIGHT (where SDFGI is reading a night sky and returns almost
# nothing) — which is also the D-079 lever.
const SDFGI_AMB_DAY := 0.58; const SDFGI_AMB_NIGHT := 0.96

# RAYLEIGH/MIE. See _apply_scenic_sky. `scatter_gain` is how much of the
# physical model is blended over the hand-authored keyframe gradient. It falls
# to zero in a storm so the canon supercell green (STORM_HOR) survives intact.
const SCATTER_CLEAR := 0.62; const SCATTER_STORM := 0.0

# Cloud lighting keyframes (hi = sunlit top, lo = shadowed base).
const CLOUD_DAY_HI := Color(1.00, 0.99, 0.96); const CLOUD_DAY_LO := Color(0.55, 0.60, 0.72)
const CLOUD_DUSK_HI := Color(1.00, 0.58, 0.28); const CLOUD_DUSK_LO := Color(0.38, 0.21, 0.29)
const CLOUD_NIGHT_HI := Color(0.11, 0.14, 0.22); const CLOUD_NIGHT_LO := Color(0.035, 0.045, 0.085)
const CLOUD_STORM_HI := Color(0.38, 0.42, 0.40); const CLOUD_STORM_LO := Color(0.075, 0.095, 0.10)
# Coverage/scale. A smaller scale = the deck sits LOWER, so storm cloud reads
# nearer and heavier; fair-weather cumulus ride high and small.
const CLOUD_FAIR_COVER := 0.24; const CLOUD_STORM_COVER := 0.97
const CLOUD_AFTERNOON_BUILD := 0.10  # Texas cumulus stack up through the day
const CLOUD_FAIR_SCALE := 0.26; const CLOUD_STORM_SCALE := 0.145
const CLOUD_FAIR_OPACITY := 0.88; const CLOUD_STORM_OPACITY := 1.0
const VEIL_FAIR := 0.16; const VEIL_STORM := 0.0   # cirrus vanish under a shelf
const CLOUD_DRIFT_FAIR := 0.0022; const CLOUD_DRIFT_STORM := 0.0090  # uv/s
# Celestial bodies. The disc is deliberately several times life size and grows
# as it drops: this is the flat-horizon money shot, not an almanac.
const SUN_DISC_HIGH := 0.016; const SUN_DISC_LOW := 0.062  # radians
# A disc pinned at 7.5 clipped to white and threw away the colour it had
# earned on the way down; the low sun dims as it reddens, like the real one.
const SUN_ENERGY_HIGH := 8.0; const SUN_ENERGY_LOW := 1.7
const MOON_SIZE := 0.036
# Horizon: exponent on the gradient (bigger = the warm band climbs higher) and
# how much haze sits in front of the dome at the skyline.
const HORIZON_EXP_HIGH := 0.34; const HORIZON_EXP_LOW := 0.86
const HAZE_DAY := 0.24; const HAZE_DUSK := 0.44; const HAZE_NIGHT := 0.20
const HAZE_STORM := 0.52
# 0.55 washed the whole prairie cream in the first aerial — aerial perspective
# is a distance cue, not a filter over the world.
const FOG_AERIAL := 0.32             # distant geometry takes the sky's colour
const FOG_SUN_SCATTER := 0.22        # haze glows toward the sun

const SKY_SHADER := """
shader_type sky;

uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;

uniform vec3 top_color : source_color = vec3(0.25, 0.42, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.71, 0.52);
uniform vec3 ground_top_color : source_color = vec3(0.86, 0.71, 0.52);
uniform vec3 ground_low_color : source_color = vec3(0.20, 0.17, 0.13);
uniform vec3 haze_color : source_color = vec3(0.85, 0.75, 0.62);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cloud_hi : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_lo : source_color = vec3(0.55, 0.60, 0.72);

uniform vec3 sun_vec = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_vec = vec3(0.0, 1.0, 0.0);
uniform vec2 cloud_drift = vec2(0.0, 0.0);

uniform float horizon_exp = 0.38;
uniform float haze_gain = 0.30;
uniform float sun_disc_size = 0.016;
uniform float sun_disc_energy = 7.5;
uniform float sun_gain = 1.0;
uniform float halo_gain = 1.0;
uniform float moon_gain = 0.0;
uniform float moon_size = 0.030;
uniform float star_gain = 0.0;
uniform float cloud_scale = 0.16;
uniform float cloud_cover = 0.36;
uniform float cloud_opacity = 0.88;
uniform float veil_gain = 0.22;
uniform float flash_gain = 0.0;
uniform float scatter_gain = 0.0;

// ── M23: RAYLEIGH / MIE, INSIDE OUR OWN DOME ────────────────────────────────
// The mandate asked for PhysicalSkyMaterial. PhysicalSky would have deleted the
// cloud decks, the moon, the star field and the supercell green — everything
// M16 built. So the PHYSICS came here instead of the sky going there.
//
// Analytic single scattering, no raymarch. Optical depth along a ray is
// approximated as scale_height / (ray.y + eps), which is the standard flat-slab
// air-mass approximation: exact at the zenith, and at grazing angles it grows
// without bound in the same way the real one does, which is the only part a
// table-flat Texas horizon actually needs. ~30 ALU, no loop, so the realtime
// radiance cubemap can still keep up with a 600 s day.
//
// Beta values are the real sea-level coefficients (per metre): Rayleigh
// 5.8/13.5/33.1e-6 for R/G/B — the lambda^-4 that makes the zenith blue and the
// sunset red is IN those three numbers, not in a colour ramp. Mie is grey and
// forward-scattering (g = 0.76), which is the aureole around a low sun and the
// white haze on a humid afternoon.
vec3 scatter_sky(vec3 dir, vec3 sun) {
	float mu = clamp(dot(dir, sun), -1.0, 1.0);
	float vy = max(dir.y, 0.0) + 0.055;
	float sy = max(sun.y, 0.0) + 0.055;
	float odvR = 8000.0 / vy;      // Rayleigh scale height 8 km
	float odvM = 1200.0 / vy;      // Mie scale height 1.2 km
	float odsR = 8000.0 / sy;
	float odsM = 1200.0 / sy;
	vec3 bR = vec3(5.8e-6, 13.5e-6, 33.1e-6);
	float bM = 21.0e-6;
	vec3 att = exp(-(bR * (odvR + odsR) + vec3(bM * 1.1 * (odvM + odsM))));
	float pr = (3.0 / (16.0 * PI)) * (1.0 + mu * mu);
	float g = 0.76;
	float pm = (3.0 / (8.0 * PI)) * ((1.0 - g * g) * (1.0 + mu * mu))
		/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	return (bR * pr * odvR + vec3(bM * pm * odvM)) * att * 22.0;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Three octaves of the tileable cloud texture. The 2.0 / 5.0 multipliers are
// INTEGERS on purpose: the drift offset wraps at 1.0 and all three octaves
// wrap with it, so the deck can drift forever without a seam or a pop.
// The base band carries most of the weight — an even mix rendered as cirrus
// stringers instead of cumulus mass (first screenshot round).
float cloud_field(vec2 uv) {
	float a = texture(cloud_tex, uv).r;
	float b = texture(cloud_tex, uv * 2.0 + vec2(0.31, 0.67)).g;
	float c = texture(cloud_tex, uv * 5.0 + vec2(0.73, 0.19)).b;
	return a * 0.70 + b * 0.22 + c * 0.08;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(up, horizon_exp));
	} else {
		col = mix(ground_top_color, ground_low_color, pow(-up, 0.42));
	}

	// The physical model rides OVER the hand-authored keyframes, never instead
	// of them. scatter_gain is driven to zero below the horizon (the night
	// keyframes carry the defect ledger's whole night-photometry history and
	// must stay comparable) and to zero in a storm (STORM_HOR's supercell green
	// is canon and no atmosphere model knows about it).
	if (scatter_gain > 0.002 && up >= 0.0) {
		col = mix(col, scatter_sky(dir, sun_vec), scatter_gain);
	}

	// Stars first: everything below can occlude them, nothing should reveal them.
	if (star_gain > 0.002 && up > -0.03) {
		vec3 sp = dir * 132.0;
		vec3 ci = floor(sp);
		vec3 cf = sp - ci;
		float mag = smoothstep(0.964, 1.0, hash13(ci));
		vec3 jit = vec3(hash13(ci + 11.3), hash13(ci + 23.7), hash13(ci + 41.1));
		float pt = (1.0 - smoothstep(0.0, 0.26, length(cf - jit))) * mag;
		pt *= 0.65 + 0.35 * hash13(ci + 7.1);
		vec3 band_n = normalize(vec3(0.36, 0.84, -0.41));
		float bd = dot(dir, band_n);
		float mw = exp(-bd * bd * 11.0)
			* (0.30 + 0.70 * texture(cloud_tex, dir.xz * 0.42 + vec2(0.5)).g);
		float fade = star_gain * smoothstep(-0.02, 0.20, up);
		col += (vec3(0.86, 0.90, 1.0) * pt * 2.9 + vec3(0.36, 0.40, 0.58) * mw * 0.085) * fade;
	}

	// Sun: broad aureole, then the disc itself well over the bloom threshold.
	float sd = dot(dir, sun_vec);
	float sa = acos(clamp(sd, -1.0, 1.0));
	col += sun_tint * (pow(max(sd, 0.0), 9.0) * 0.45 + pow(max(sd, 0.0), 2.2) * 0.075) * halo_gain;
	col += sun_tint * (1.0 - smoothstep(sun_disc_size * 0.80, sun_disc_size, sa))
		* sun_disc_energy * sun_gain;

	// Moon: a lit sphere, not a dot — terminator plus maria off the cloud noise.
	if (moon_gain > 0.002) {
		vec3 mr = normalize(cross(vec3(0.0, 1.0, 0.0), moon_vec) + vec3(1e-5, 0.0, 0.0));
		vec3 mu = cross(moon_vec, mr);
		vec2 muv = vec2(dot(dir, mr), dot(dir, mu)) / moon_size;
		float mrad = length(muv);
		if (mrad < 2.4) {
			float mdisc = 1.0 - smoothstep(0.93, 1.0, mrad);
			vec3 n = vec3(muv, sqrt(max(0.0, 1.0 - min(mrad * mrad, 1.0))));
			float lam = clamp(dot(normalize(vec3(0.52, 0.28, 0.81)), n), 0.0, 1.0);
			float maria = texture(cloud_tex, muv * 0.30 + vec2(0.5)).r;
			vec3 mc = mix(vec3(0.66, 0.68, 0.76), vec3(0.97, 0.97, 1.0), maria);
			col += mc * mdisc * (0.30 + 0.85 * lam) * 2.3 * moon_gain;
			col += vec3(0.52, 0.60, 0.86) * exp(-mrad * 1.9) * 0.10 * moon_gain;
		}
	}

	// TWO decks, projected onto planes overhead: both converge and pile up
	// toward the horizon with true perspective, which is the whole North Texas
	// sky in one trick. The veil rides much higher (a larger uv factor packs
	// more field into the same angle, which is exactly why cirrus look fine
	// and cumulus look coarse) and drifts faster. The cumulus deck below it
	// self-shadows: the field is sampled one step sunward, so the bulge facing
	// the sun lights and the far side falls to base grey.
	float ca = 0.0;
	vec3 cc = vec3(0.0);
	if (up > 0.010) {
		// A pure dir.xz/up plane projection stretches WITHOUT BOUND at the
		// horizon: the sampled field mips out to flat mid-grey, which lands
		// right on the coverage threshold and smears half the sky into cirrus
		// streaks (round-two finding). Softening the denominator is the curved
		// -deck approximation — the deck still converges, but it stops being
		// infinite, so cloud stays cloud all the way down to the skyline.
		vec2 base = dir.xz / (up + 0.20);
		float fade = smoothstep(0.010, 0.11, up);
		vec2 vuv = base * cloud_scale * 2.4 + cloud_drift * 1.7 + vec2(0.37, 0.81);
		float va = smoothstep(0.50, 0.80, cloud_field(vuv)) * veil_gain * fade;
		col = mix(col, mix(cloud_lo, cloud_hi, 0.80), clamp(va, 0.0, 1.0));
		vec2 uv = base * cloud_scale + cloud_drift;
		float d = cloud_field(uv);
		float lo = mix(0.70, 0.22, cloud_cover);
		float hi = lo + 0.13;
		vec2 so = normalize(sun_vec.xz + vec2(1e-4, 1e-4)) * 0.035;
		float lit = clamp(0.5 + (d - cloud_field(uv + so)) * 9.0, 0.0, 1.0);
		float thick = smoothstep(lo, hi + 0.26, d);
		cc = mix(cloud_lo, cloud_hi, clamp(lit * (1.0 - 0.60 * thick) + 0.14, 0.0, 1.0));
		cc += sun_tint * pow(max(sd, 0.0), 30.0) * 0.85;   // silver lining
		ca = smoothstep(lo, hi, d) * cloud_opacity * fade;
	}
	col = mix(col, cc, clamp(ca, 0.0, 1.0));

	// Lightning lights the deck from the inside.
	col += vec3(0.86, 0.90, 1.0) * flash_gain * (ca * 1.10 + 0.10);

	// Two haze layers, in front of everything: a wide skirt and a tight band
	// right on the horizon line. This is what gives a table-flat map depth.
	float e = 1.0 - clamp(abs(up), 0.0, 1.0);
	col = mix(col, haze_color,
		clamp(pow(e, 5.0) * haze_gain + pow(e, 26.0) * haze_gain * 0.55, 0.0, 1.0));

	COLOR = col;
}
"""

# UI (slot: centre-top y~180, below the race timer at 130).
const BANNER_OFFSET := 180; const BANNER_SECONDS := 6.0
const WARN_TEXT := "MEGAPLEX WEATHER SERVICE — STORM WARNING"
const CLEAR_TEXT := "MEGAPLEX WEATHER SERVICE — ALL CLEAR"
const WARN_COLOR := Color(1.0, 0.72, 0.2); const CLEAR_COLOR := Color(0.4, 0.9, 0.5)

# ============================== PUBLIC API ===================================
var time_of_day: float = START_HOUR  # hours, 0..24
var is_night := false; var is_storm := false

# ============================== STATE ========================================
var main_ref: Node = null; var _sun: DirectionalLight3D = null; var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null; var _rng := RandomNumberGenerator.new()
var _state: int = WState.CLEAR; var _state_t := 0.0
var _mix := 0.0                      # 0 fair -> 1 full supercell
var _wet_look := 0.0                 # M22: visual wetness, lags grip on purpose
var _wind_dir := Vector3.RIGHT; var _wind_t := 0.0
const GROUP_REFRESH := 0.4           # group snapshot cadence (s)
var _grp_t := 0.0; var _towables: Array[Node] = []; var _cops: Array[Node] = []
var _flash_t := 0.0; var _strike_t := 0.0; var _thunder_delay := 0.0
var _siren_armed := false; var _siren_t := 0.0
var _rain: GPUParticles3D = null; var _rain_mat: ParticleProcessMaterial = null
var _thunder: AudioStreamPlayer = null; var _siren: AudioStreamPlayer = null
var _ui: CanvasLayer = null; var _banner: Label = null; var _banner_t := 0.0
var _sky_shader: ShaderMaterial = null   # M16: owns the dome when installed
var _sdfgi_live := false                 # M23: SDFGI on -> sky ambient gives way
var _volfog_live := false                # M23: this system drives fog density
var _cam_attr: CameraAttributes = null   # M23: the ToD exposure ramp writes here
var _cloud_drift := Vector2(0.31, 0.17)  # uv offset, wrapped to [0,1)

func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false)
		return  # SMOKE GATE: no UI, no audio, no env mutation — byte-identical
	set_process(false)               # everything runs on the physics tick
	var s: Variant = main.get("sun"); var we: Variant = main.get("world_env")
	if s is DirectionalLight3D and is_instance_valid(s): _sun = s
	if we is WorldEnvironment and is_instance_valid(we):
		_env = (we as WorldEnvironment).environment
	if _sun == null or _env == null:
		set_physics_process(false)   # world handles missing: no-op forever
		return
	if _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
		_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	_install_scenic_sky()
	# M23: pick up the rig render_pipeline.gd built, so this system knows which
	# of its per-frame writes are live. Guarded by name: an environment without
	# these fields degrades to the M22 behaviour instead of erroring.
	_sdfgi_live = RENDER.on("sdfgi") and "sdfgi_enabled" in _env
	_volfog_live = RENDER.on("volfog") and "volumetric_fog_enabled" in _env
	if we is WorldEnvironment and is_instance_valid(we):
		var ca: Variant = (we as WorldEnvironment).camera_attributes
		if ca is CameraAttributes and RENDER.on("exposure"):
			_cam_attr = ca
	_rng.seed = RNG_SEED
	_thunder = _make_voice(_build_thunder(), THUNDER_FAR_DB)
	_siren = _make_voice(_build_siren(), SIREN_DB)
	_state_t = _rng.randf_range(CLEAR_RANGE.x, CLEAR_RANGE.y)
	_build_ui()

func _physics_process(delta: float) -> void:
	if _sun == null or not is_instance_valid(_sun):
		set_physics_process(false)   # sun freed under us: stand down for good
		return
	# Group snapshots on a timer (membership churns slowly; positions are read
	# live off the cached refs) — avoids a fresh Array allocation every tick.
	_grp_t -= delta
	if _grp_t <= 0.0:
		_grp_t = GROUP_REFRESH
		_towables = get_tree().get_nodes_in_group("towable")
		_cops = get_tree().get_nodes_in_group("police")
	time_of_day = fposmod(time_of_day + delta * 24.0 / DAY_LENGTH, 24.0)
	_update_weather(delta)
	_drift_clouds(delta)
	_apply_sky()
	_update_lightning(delta)
	_update_rain()
	_update_wind(delta)
	_update_grip()
	_update_wet_look(delta)
	_update_siren(delta)
	_update_banner(delta)

# ============================== WEATHER MACHINE ==============================
func _update_weather(delta: float) -> void:
	_state_t -= delta
	match _state:
		WState.CLEAR:
			_mix = move_toward(_mix, 0.0, delta / CLEARING_SECONDS)
			if _state_t <= 0.0:
				_state = WState.BUILDING; _state_t = BUILDING_SECONDS
				var a := _rng.randf_range(0.0, TAU)  # per-storm wind heading
				_wind_dir = Vector3(cos(a), 0.0, sin(a))
		WState.BUILDING:
			_mix = move_toward(_mix, BUILD_MIX, delta * BUILD_MIX / BUILDING_SECONDS)
			if _state_t <= 0.0:
				_state = WState.STORM
				_state_t = _rng.randf_range(STORM_RANGE.x, STORM_RANGE.y)
				_strike_t = _rng.randf_range(STRIKE_RANGE.x, STRIKE_RANGE.y)
				_siren_armed = _rng.randf() < SIREN_CHANCE  # this is Texas
				_aim_rain(); _show_banner(WARN_TEXT, WARN_COLOR)
		WState.STORM:
			_mix = move_toward(_mix, 1.0, delta * (1.0 - BUILD_MIX) / STORM_RAMP_SECONDS)
			if _state_t <= 0.0:
				_state = WState.CLEARING; _state_t = CLEARING_SECONDS
				_show_banner(CLEAR_TEXT, CLEAR_COLOR)
		WState.CLEARING:
			_mix = move_toward(_mix, 0.0, delta / CLEARING_SECONDS)
			if _state_t <= 0.0:
				_state = WState.CLEAR
				_state_t = _rng.randf_range(CLEAR_RANGE.x, CLEAR_RANGE.y)
	is_storm = _state == WState.STORM

# ============================== DAY/NIGHT SKY ================================
## Everything is recomputed from scratch each frame, so the lightning flash is
## a pure transient multiplier and always "restores exactly" by construction.
func _apply_sky() -> void:
	var elev := MAX_ELEV_DEG * cos((time_of_day - NOON_HOUR) * TAU / 24.0)
	is_night = elev < 0.0
	var azi := (NOON_HOUR - time_of_day) * AZIMUTH_DEG_PER_HOUR
	# abs() keeps the pitch continuous at the horizon and doubles as the moon:
	# by the crossover the energy has already faded to near-night levels.
	_sun.rotation_degrees = Vector3(-clampf(absf(elev), MIN_APPLIED_ELEV, 88.0), azi, 0.0)
	var energy: float; var sun_col: Color
	if elev >= SUNSET_WARM_ELEV:
		var k := (elev - SUNSET_WARM_ELEV) / (MAX_ELEV_DEG - SUNSET_WARM_ELEV)
		energy = lerpf(WARM_SUN_ENERGY, NOON_SUN_ENERGY, clampf(k, 0.0, 1.0))
		sun_col = DAY_SUN
	elif elev >= 0.0:  # the enormous Texas sunset: warm, red, huge
		var k := elev / SUNSET_WARM_ELEV
		energy = lerpf(HORIZON_SUN_ENERGY, WARM_SUN_ENERGY, k)
		sun_col = SUNSET_SUN.lerp(DAY_SUN, k)
	else:              # night: cool blue moonlight stand-in
		var k := clampf(elev / NIGHT_FADE_ELEV, 0.0, 1.0)
		energy = lerpf(HORIZON_SUN_ENERGY, NIGHT_SUN_ENERGY, k)
		sun_col = SUNSET_SUN.lerp(NIGHT_SUN, k)
	var daylight := clampf(elev / SUNSET_WARM_ELEV, 0.0, 1.0)
	var ambient := lerpf(NIGHT_AMBIENT, DAY_AMBIENT, clampf((elev + 2.0) / 14.0, 0.0, 1.0))

	# Sky colours: dawn/day/dusk/night keyframes, lerped by elevation, with the
	# warm edge picked by which side of solar noon we are on.
	var edge_top := DAWN_TOP if time_of_day < NOON_HOUR else DUSK_TOP
	var edge_hor := DAWN_HOR if time_of_day < NOON_HOUR else DUSK_HOR
	var top: Color; var hor: Color
	if elev >= SKY_DAY_ELEV:
		top = DAY_TOP; hor = DAY_HOR
	elif elev >= 0.0:
		var k := elev / SKY_DAY_ELEV
		top = edge_top.lerp(DAY_TOP, k); hor = edge_hor.lerp(DAY_HOR, k)
	elif elev >= NIGHT_FADE_ELEV:
		var k := elev / NIGHT_FADE_ELEV
		top = edge_top.lerp(NIGHT_TOP, k); hor = edge_hor.lerp(NIGHT_HOR, k)
	else:
		top = NIGHT_TOP; hor = NIGHT_HOR

	# Supercell overlay: desaturate/darken toward the green-gray storm palette.
	energy *= lerpf(1.0, STORM_SUN_FACTOR, _mix)
	ambient *= lerpf(1.0, STORM_AMBIENT_FACTOR, _mix)
	sun_col = sun_col.lerp(STORM_SUN, _mix)
	top = top.lerp(STORM_TOP, _mix); hor = hor.lerp(STORM_HOR, _mix)
	if _flash_t > 0.0:  # lightning: transient only, restored next frame
		energy *= FLASH_SUN_MULT; ambient += FLASH_AMBIENT_ADD
	_sun.light_energy = energy; _sun.light_color = sun_col
	# SDFGI and sky ambient are both "light arriving from the environment"; with
	# both at full strength the world double-counts and noon goes milky. Day
	# gives way, night keeps nearly all of it (SDFGI reading a night sky returns
	# almost nothing) — see SDFGI_AMB_* and D-079.
	if _sdfgi_live:
		ambient *= lerpf(SDFGI_AMB_NIGHT, SDFGI_AMB_DAY, daylight)
	_env.ambient_light_energy = ambient
	var fog_col := NIGHT_FOG.lerp(DAY_FOG, daylight).lerp(STORM_FOG, _mix)
	var ground := NIGHT_GROUND.lerp(DAY_GROUND, daylight).lerp(STORM_GROUND, _mix)
	_env.fog_light_color = fog_col
	_env.fog_density = lerpf(lerpf(NIGHT_FOG_DENSITY, DAY_FOG_DENSITY, daylight),
			STORM_FOG_DENSITY, _mix)
	_drive_volumetric_fog(elev, daylight)
	_drive_exposure(daylight)
	if _sky_mat != null:  # shared material: mutate in place, never replace
		_sky_mat.sky_top_color = top
		_sky_mat.sky_horizon_color = hor
		_sky_mat.ground_horizon_color = hor
		_sky_mat.ground_bottom_color = ground
	if _sky_shader != null:
		_apply_scenic_sky(elev, azi, top, hor, ground, fog_col, sun_col)


# ====================== M23: VOLUMETRIC FOG + EXPOSURE =======================
## The air, per frame. `render_pipeline.gd` turned volumetric fog on and sized
## the froxel grid; what is IN the air is a function of the clock and the storm,
## and the clock and the storm live here.
##
## THE SHAFT HOUR is the point of this function. A hump on sun ELEVATION (not on
## the hour, so it survives anyone retuning DAY_LENGTH) centred at
## VFOG_DUSK_ELEV: broad enough to cover roughly 16:30–19:30 game time, peaking
## where the sun is low enough to rake between the towers and still bright
## enough to carry a beam. At noon the air is nearly empty — a dry North Texas
## noon has nothing in it and volumetric fog at noon just looks like a dirty
## lens.
func _drive_volumetric_fog(elev: float, daylight: float) -> void:
	if not _volfog_live or _env == null:
		return
	var dusk := clampf(1.0 - absf(elev - VFOG_DUSK_ELEV) / VFOG_DUSK_WIDTH, 0.0, 1.0)
	var night := 1.0 - daylight
	var d := lerpf(VFOG_NIGHT, VFOG_NOON, daylight)
	d = lerpf(d, VFOG_DUSK, dusk)
	d = lerpf(d, VFOG_STORM, _mix)
	var alb := VFOG_ALBEDO_NIGHT.lerp(VFOG_ALBEDO_DAY, daylight) \
		.lerp(VFOG_ALBEDO_DUSK, dusk).lerp(VFOG_ALBEDO_STORM, _mix)
	_env.volumetric_fog_density = d
	_env.volumetric_fog_albedo = alb
	# The city's own light dome. Night only, and gone in a storm — under a
	# shelf cloud the glow is smothered, not amplified.
	_env.volumetric_fog_emission = VFOG_EMIT_NIGHT
	_env.volumetric_fog_emission_energy = VFOG_EMIT_ENERGY * night * (1.0 - _mix)
	_env.volumetric_fog_anisotropy = lerpf(VFOG_ANISO_CLEAR, VFOG_ANISO_STORM, _mix)


## Deterministic exposure, in stops, as a pure function of daylight and the
## storm mix. Same time_of_day always gives the same exposure — which is the
## whole reason this is not `auto_exposure_enabled`: every quality number in
## docs/qa/defects.md is screenshot photometry, and an auto-exposing plate
## captured 8 frames after a camera teleport is not comparable to anything.
func _drive_exposure(daylight: float) -> void:
	if _cam_attr == null:
		return
	var dusk := 1.0 - absf(daylight * 2.0 - 1.0)   # hump at half daylight
	var s := lerpf(EXP_NIGHT, EXP_NOON, daylight)
	s = lerpf(s, EXP_DUSK, dusk * 0.6)
	s = lerpf(s, EXP_STORM, _mix)
	_cam_attr.exposure_multiplier = RENDER.stops(s)


# ============================== SCENIC SKY (M16) =============================
## Install the custom dome. Runs only on non-smoke boots (setup returns before
## this in smoke mode), and only if main actually built a Sky — a missing
## handle just leaves the M4 gradient in place.
func _install_scenic_sky() -> void:
	if _env == null or _env.sky == null:
		return
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("cloud_tex", TEX.cloud_noise_texture())
	# The deck drifts and the light swings, so the radiance cubemap has to keep
	# up. REALTIME is the mode built for animated skies, and in 4.7 it REQUIRES
	# a 256 radiance size — set the size first or the renderer logs a warning
	# and overrides you (screenshot-run-caught; the headless gate never renders
	# a sky, so this one can only be found with a window open).
	_env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	_env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	_env.sky.sky_material = m
	_sky_shader = m
	_sky_mat = null                  # the gradient material is retired
	# Depth cues main.gd could not set without knowing the sky: distant geometry
	# takes the dome's own colour, and haze glows toward the sun. Guarded by
	# name so an engine without them degrades instead of erroring.
	if "fog_aerial_perspective" in _env:
		_env.fog_aerial_perspective = FOG_AERIAL
	if "fog_sun_scatter" in _env:
		_env.fog_sun_scatter = FOG_SUN_SCATTER


## Cloud drift: real-time only, wrapped to [0,1) so it never loses precision
## and never pops (all three shader octaves use integer multipliers). Reads
## the machine's per-storm wind heading; writes nothing back to it.
func _drift_clouds(delta: float) -> void:
	if _sky_shader == null:
		return
	var speed := lerpf(CLOUD_DRIFT_FAIR, CLOUD_DRIFT_STORM, _mix) * delta
	_cloud_drift.x = fposmod(_cloud_drift.x + _wind_dir.x * speed, 1.0)
	_cloud_drift.y = fposmod(_cloud_drift.y + _wind_dir.z * speed, 1.0)


## Push the frame's look onto the dome. Every argument is a value _apply_sky
## already computed — this function derives nothing about time or weather.
func _apply_scenic_sky(elev: float, azi: float, top: Color, hor: Color,
		ground: Color, fog_col: Color, sun_col: Color) -> void:
	var m := _sky_shader
	var ar := deg_to_rad(azi)
	# TRUE sun direction, signed elevation: the machine clamps the LIGHT's pitch
	# to 3 deg so shadows never graze, but the disc has to be able to touch the
	# horizon and go under it. The moon rides the light's mirrored pitch, which
	# is exactly where the night "sun" already points.
	var sun_dir := Basis.from_euler(Vector3(deg_to_rad(-elev), ar, 0.0)).z
	var moon_dir := Basis.from_euler(Vector3(deg_to_rad(-absf(elev)), ar, 0.0)).z
	var low := 1.0 - clampf(elev / SUNSET_WARM_ELEV, 0.0, 1.0)   # 1 on the horizon
	var below := clampf(-elev / 6.0, 0.0, 1.0)

	var chi: Color
	var clo: Color
	if elev >= SKY_DAY_ELEV:
		chi = CLOUD_DAY_HI; clo = CLOUD_DAY_LO
	elif elev >= 0.0:
		var k := elev / SKY_DAY_ELEV
		chi = CLOUD_DUSK_HI.lerp(CLOUD_DAY_HI, k); clo = CLOUD_DUSK_LO.lerp(CLOUD_DAY_LO, k)
	elif elev >= NIGHT_FADE_ELEV:
		var k := elev / NIGHT_FADE_ELEV
		chi = CLOUD_DUSK_HI.lerp(CLOUD_NIGHT_HI, k); clo = CLOUD_DUSK_LO.lerp(CLOUD_NIGHT_LO, k)
	else:
		chi = CLOUD_NIGHT_HI; clo = CLOUD_NIGHT_LO
	chi = chi.lerp(CLOUD_STORM_HI, _mix); clo = clo.lerp(CLOUD_STORM_LO, _mix)

	var haze := lerpf(HAZE_DUSK, HAZE_DAY, clampf(elev / SKY_DAY_ELEV, 0.0, 1.0)) \
			if elev >= 0.0 else lerpf(HAZE_DUSK, HAZE_NIGHT, below)
	# Cumulus build through the afternoon and die back overnight, on top of
	# whatever the supercell overlay is asking for.
	var build := CLOUD_AFTERNOON_BUILD * clampf(sin((time_of_day - 8.0) / 12.0 * PI), 0.0, 1.0)

	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("horizon_color", hor)
	m.set_shader_parameter("ground_top_color", hor)
	m.set_shader_parameter("ground_low_color", ground)
	m.set_shader_parameter("haze_color", hor.lerp(fog_col, 0.4))
	m.set_shader_parameter("sun_tint", sun_col)
	m.set_shader_parameter("cloud_hi", chi)
	m.set_shader_parameter("cloud_lo", clo)
	m.set_shader_parameter("sun_vec", sun_dir)
	m.set_shader_parameter("moon_vec", moon_dir)
	m.set_shader_parameter("cloud_drift", _cloud_drift)
	m.set_shader_parameter("horizon_exp", lerpf(HORIZON_EXP_HIGH, HORIZON_EXP_LOW, low))
	m.set_shader_parameter("haze_gain", lerpf(haze, HAZE_STORM, _mix))
	m.set_shader_parameter("sun_disc_size", lerpf(SUN_DISC_HIGH, SUN_DISC_LOW, low))
	m.set_shader_parameter("sun_disc_energy", lerpf(SUN_ENERGY_HIGH, SUN_ENERGY_LOW, low))
	m.set_shader_parameter("sun_gain", clampf((elev + 1.0) / 2.5, 0.0, 1.0))
	m.set_shader_parameter("halo_gain", clampf((elev + 5.0) / 8.0, 0.0, 1.0))
	m.set_shader_parameter("moon_gain", clampf(-(elev + 1.0) / 4.0, 0.0, 1.0))
	m.set_shader_parameter("moon_size", MOON_SIZE)
	m.set_shader_parameter("star_gain",
		clampf(-(elev + 1.5) / 7.0, 0.0, 1.0) * (1.0 - _mix))
	m.set_shader_parameter("cloud_cover",
		lerpf(CLOUD_FAIR_COVER + build, CLOUD_STORM_COVER, _mix))
	m.set_shader_parameter("cloud_scale", lerpf(CLOUD_FAIR_SCALE, CLOUD_STORM_SCALE, _mix))
	m.set_shader_parameter("cloud_opacity",
		lerpf(CLOUD_FAIR_OPACITY, CLOUD_STORM_OPACITY, _mix))
	m.set_shader_parameter("veil_gain", lerpf(VEIL_FAIR, VEIL_STORM, _mix))
	m.set_shader_parameter("flash_gain", clampf(_flash_t / FLASH_SECONDS, 0.0, 1.0))
	# Rayleigh/Mie blend. Off below the horizon, off in a storm. `--env-no-
	# scatter` prices it against the M16 dome from the same tree.
	var sg := 0.0
	if RENDER.on("scatter"):
		sg = lerpf(SCATTER_CLEAR, SCATTER_STORM, _mix) \
			* smoothstep(-1.0, 8.0, elev)
	m.set_shader_parameter("scatter_gain", sg)

# ============================== LIGHTNING ====================================
func _update_lightning(delta: float) -> void:
	_flash_t = maxf(_flash_t - delta, 0.0)
	if _thunder_delay > 0.0:  # pending rumble keeps counting even post-storm
		_thunder_delay -= delta
		if _thunder_delay <= 0.0 and _thunder != null: _thunder.play()
	if _state != WState.STORM: return
	_strike_t -= delta
	if _strike_t > 0.0: return
	_strike_t = _rng.randf_range(STRIKE_RANGE.x, STRIKE_RANGE.y)
	_flash_t = FLASH_SECONDS
	var d := _rng.randf_range(THUNDER_RANGE.x, THUNDER_RANGE.y)
	_thunder_delay = d
	if _thunder != null:  # closer strike (shorter delay) = louder rumble
		var k := (d - THUNDER_RANGE.x) / (THUNDER_RANGE.y - THUNDER_RANGE.x)
		_thunder.volume_db = lerpf(THUNDER_NEAR_DB, THUNDER_FAR_DB, k)

# ============================== RAIN =========================================
func _update_rain() -> void:
	var want := _state == WState.STORM or _state == WState.CLEARING
	if _rain == null:
		if not want: return
		_build_rain()  # lazy: fair-weather boots never pay for particles
	var ratio := clampf((_mix - BUILD_MIX) / (1.0 - BUILD_MIX), 0.0, 1.0)
	_rain.amount_ratio = ratio  # ramps in with the storm, out through clearing
	_rain.emitting = want and ratio > 0.02
	var pv := _player()
	if pv != null:  # follow the actor every frame (world-space particles)
		_rain.position = pv.global_position + Vector3.UP * RAIN_HEIGHT

func _build_rain() -> void:
	_rain = GPUParticles3D.new(); _rain.name = "RainVolume"
	_rain.amount = RAIN_AMOUNT; _rain.lifetime = RAIN_LIFETIME
	_rain.local_coords = false; _rain.emitting = false; _rain.amount_ratio = 0.0
	_rain.visibility_aabb = AABB(Vector3(-64, -40, -64), Vector3(128, 80, 128))
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = RAIN_BOX * 0.5
	_rain_mat.spread = 0.0
	_rain_mat.initial_velocity_min = RAIN_SPEED_MIN
	_rain_mat.initial_velocity_max = RAIN_SPEED_MAX
	_rain.process_material = _rain_mat
	var streak := BoxMesh.new(); streak.size = RAIN_STREAK
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = RAIN_COLOR
	streak.material = mat; _rain.draw_pass_1 = streak
	add_child(_rain)  # Node3D under a plain Node: position acts as global
	_aim_rain()

## Point the fall direction down with a slight per-storm wind lean.
func _aim_rain() -> void:
	if _rain_mat == null: return
	_rain_mat.direction = (Vector3.DOWN + _wind_dir * RAIN_WIND_TILT).normalized()
	_rain_mat.gravity = Vector3(0.0, RAIN_GRAVITY, 0.0) + _wind_dir * 3.0

# ============================== WIND =========================================
## Gusts on the actor plus every unfrozen towable/police body within 100 m
## ("towable" covers cruisers and crash debris; frozen traffic is immune).
## Forces only exist on rigid bodies — the on-foot CharacterBody3D is centred
## in the gust radius but never shoved (no apply_central_force on it).
func _update_wind(delta: float) -> void:
	if _mix <= 0.01:
		return  # distant gusts begin with BUILDING and die with the mix
	_wind_t += delta
	var gust := 0.5 + 0.5 * sin(_wind_t * TAU * WIND_GUST_HZ)
	var force := _wind_dir * (lerpf(WIND_MIN_N, WIND_MAX_N, gust) * _mix)
	var pv := _player()
	if pv == null: return
	var ppos := pv.global_position
	if pv is RigidBody3D:
		(pv as RigidBody3D).apply_central_force(force)
	for n in _towables:
		# is_instance_valid FIRST: `is` on a freed instance is itself a script
		# error, and cached group refs can go stale between 0.4 s rescans.
		if is_instance_valid(n) and n is RigidBody3D and (n as Node).is_inside_tree():
			var b := n as RigidBody3D
			if not b.freeze and b != pv \
					and b.global_position.distance_to(ppos) <= WIND_RADIUS:
				b.apply_central_force(force)

# ============================== WET ROADS ====================================
## Both branches run every physics frame, so Tab swaps and fresh cruiser
## spawns self-heal and no vehicle is EVER left wet after the storm. Grip
## belongs to vehicles, never the actor: read main.vehicle directly (guarded to
## RaycastVehicle) so the parked rig wets/dries even while the player walks.
func _update_grip() -> void:
	var wet := _state == WState.STORM or _state == WState.CLEARING
	var grip := WET_GRIP if wet else DRY_GRIP
	var pv: Variant = main_ref.get("vehicle") if main_ref != null else null
	if pv is RaycastVehicle and is_instance_valid(pv) and (pv as Node).is_inside_tree():
		(pv as RaycastVehicle).grip_modifier = grip
	for n in _cops:
		# is_instance_valid FIRST — see _update_wind; freed cruisers linger in
		# the cache for up to 0.4 s (despawns on heat drops, flips, trims).
		if is_instance_valid(n) and n is RaycastVehicle and (n as Node).is_inside_tree():
			(n as RaycastVehicle).grip_modifier = grip


## M22: the LOOK of a wet road, which until now did not exist — grip has been
## dropping to 0.72 in the rain since M16 while the pavement went on rendering
## bone dry. This is deliberately NOT the same signal as grip.
##
## Grip is a state flag: wet or not, instantly, because a tyre either has water
## under it or it does not. Wetness is a QUANTITY with memory: pavement soaks in
## under a minute and then takes several to give it back, so the road stays dark
## and mirrored long after the last drop and through the whole CLEARING ramp.
## Tying the look to the flag would snap the entire city from dry to wet in one
## frame, which is the single most obvious way to make weather look fake.
##
## Costs one shader-parameter write on 3 materials per physics tick. Inert in
## smoke mode (setup returns before _physics_process is ever enabled) and inert
## under `--gfx-legacy` (the registry the setter walks is never populated).
func _update_wet_look(delta: float) -> void:
	var target := 1.0 if _state == WState.STORM else 0.0
	var rate := 1.0 / (WET_SOAK_SECONDS if target > _wet_look else WET_DRY_SECONDS)
	_wet_look = move_toward(_wet_look, target, delta * rate)
	SHADERS.set_wetness(_wet_look)

# ============================== TORNADO SIREN ================================
func _update_siren(delta: float) -> void:
	if _siren == null: return
	if _siren_armed and _state == WState.STORM and _mix >= SIREN_PEAK_MIX:
		_siren_armed = false; _siren_t = SIREN_PLAY_SECONDS
		_siren.play()
	if _siren_t > 0.0:
		_siren_t -= delta
		if _siren_t <= 0.0 and _siren.playing: _siren.stop()

# ============================== UI ===========================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 9; add_child(_ui)    # between race timer (8) and police (12)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, BANNER_OFFSET)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.visible = false; _ui.add_child(_banner)

func _show_banner(text: String, col: Color) -> void:
	if _banner == null: return
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0; _banner.visible = true; _banner_t = BANNER_SECONDS

func _update_banner(delta: float) -> void:
	if _banner == null or _banner_t <= 0.0: return
	_banner_t -= delta
	_banner.modulate.a = clampf(_banner_t / (BANNER_SECONDS * 0.35), 0.0, 1.0)
	if _banner_t <= 0.0: _banner.visible = false

# ============================== SYNTHESIS ====================================
## Thunder: white noise through two cascaded one-pole lowpasses (deep rumble),
## short attack, ~2.5 s exponential decay with a slow rolling modulation.
func _build_thunder() -> AudioStreamWAV:
	var n := int(THUNDER_SECONDS * float(MIX_RATE))
	var samples := PackedFloat32Array(); samples.resize(n)
	var lp1 := 0.0; var lp2 := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		lp1 += 0.06 * (_rng.randf_range(-1.0, 1.0) - lp1)
		lp2 += 0.10 * (lp1 - lp2)
		var attack := minf(float(i) / 900.0, 1.0)
		var roll := exp(-t * 1.8) * (0.7 + 0.3 * sin(t * 23.0))
		samples[i] = clampf(lp2 * 12.0, -0.95, 0.95) * attack * roll
	return _wav(samples, false)

## Tornado siren: sine whose frequency follows a slow symmetric triangle
## 400 -> 800 -> 400 Hz across the loop. The discrete triangle averages to
## exactly 600 Hz, so the 10 s loop holds 6000 whole cycles — click-free.
func _build_siren() -> AudioStreamWAV:
	var n := int(SIREN_LOOP_SECONDS * float(MIX_RATE))
	var samples := PackedFloat32Array(); samples.resize(n)
	var phase := 0.0
	for i in n:
		var x := float(i) / float(n)
		var tri := 2.0 * x if x < 0.5 else 2.0 * (1.0 - x)
		var hz := SIREN_LOW_HZ + (SIREN_HIGH_HZ - SIREN_LOW_HZ) * tri
		samples[i] = 0.8 * sin(phase)
		phase += TAU * hz / float(MIX_RATE)
	return _wav(samples, true)

func _wav(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray(); bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE; w.stereo = false; w.data = bytes
	if looping:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0; w.loop_end = samples.size()
	return w

# ============================== PLUMBING =====================================
func _make_voice(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()  # non-positional: weather is everywhere
	p.stream = stream; p.volume_db = db
	add_child(p); return p

## The actor the weather centres on: character when on foot, vehicle otherwise.
func _player() -> Node3D:
	if main_ref == null: return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var v: Variant = main_ref.get("vehicle")
	return v if v is Node3D and is_instance_valid(v) \
			and (v as Node).is_inside_tree() else null

## Playing streams at quit leak in 4.7.1 — stop ours, then hold the teardown
## one audio mix period so the mix thread consumes ALL queued stops (incl.
## vehicle_audio's engine loop, whose _exit_tree ran just before this one)
## before ObjectDB cleanup. Real-time only; frame determinism untouched.
func _exit_tree() -> void:
	for p: Variant in [_thunder, _siren]:
		if p is AudioStreamPlayer and is_instance_valid(p):
			(p as AudioStreamPlayer).stop()
	if _thunder != null:  # non-smoke boots only
		OS.delay_msec(150)  # > one dummy/headless mix period (~93 ms)
