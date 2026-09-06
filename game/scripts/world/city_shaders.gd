extends RefCounted
## CUSTOM SHADER KIT — the project's first surface shaders.
##
## Doctrine, unchanged: zero asset files. Every shader below is an inline source
## string compiled into a `Shader` at boot, exactly the way `sky_weather.gd`
## owns the sky dome. Every texture these shaders sample is built pixel-by-pixel
## by `city_textures.gd`. Nothing here reads a `.tres`, a `.glsl` or an image.
##
## RENDERER: Forward+ (what this project runs). Everything here is also
## Mobile-safe and Compatibility-safe by construction — no SCREEN_TEXTURE, no
## DEPTH_TEXTURE, no compute, no dynamic loops, no `discard` in an opaque pass.
## The one renderer feature the road shader leans on is the REALTIME radiance
## cubemap that `sky_weather.gd` already pays for (`Sky.PROCESS_MODE_REALTIME`,
## sky_weather.gd:_install_scenic_sky). A wet road at roughness 0.04 mirrors the
## actual storm deck because that cubemap is already live and already budgeted.
##
## THE A/B TOGGLE — `--gfx-legacy`
## Every builder in this file is a fork: with the flag, it returns the exact
## StandardMaterial3D the project shipped before; without it, the shader. This
## is the `--perf-mm-cast=` precedent (perf_harness.gd:191-206) applied to
## shaders, and it exists for one reason: this machine drifts up to 40% between
## runs, so a before/after taken 20 minutes apart is not evidence. One tree, two
## arms, interleaved in one session, or the number is worthless.
##
##   godot -- --perf --perf-repeat=3                  # shaders ON
##   godot -- --perf --perf-repeat=3 --gfx-legacy     # shaders OFF
##   godot -- --shot            /  godot -- --shot --gfx-legacy
##
## SAMPLE BUDGET is the currency in a fragment shader, and the road shader is a
## NET SAVING: the StandardMaterial3D it replaces is world-triplanar, and Godot's
## triplanar path samples every texture THREE times and blends by the normal.
## The road shader projects flat on world XZ instead — 2 samples total — and
## spends the saved one on a normal map, macro variation, wheel polish and rain.
## Detail went up; sample count went down.

const TEX := preload("res://scripts/world/city_textures.gd")


# ============================== THE TOGGLE ===================================
## Read once. `-1` unknown, `0` shaders, `1` legacy. Static so the ~20 material
## builders that ask do not each re-parse the command line.
static var _legacy := -1


static func legacy() -> bool:
	if _legacy < 0:
		_legacy = 1 if OS.get_cmdline_user_args().has("--gfx-legacy") else 0
	return _legacy == 1


# ======================= ROAD / PAVEMENT SURFACE =============================
## The single highest-leverage surface in the game. `mat_asphalt` alone covers
## ~566,000 m² (greybox_city.gd:176-177 is a 690 x 526 m slab under all of
## downtown) and it is what the player stares at from a car for the whole game.
##
## What it adds over a flat albedo + a roughness number:
##  1. MICRO NORMAL — the surface stops being geometrically perfect glass. This
##     is most of the "arcade" fix on its own: a road with no normal detail has
##     no specular breakup, so it reads as painted cardboard at every angle.
##  2. MACRO VARIATION — repave slabs, drainage undulation, oil/grime blotching
##     and seams on a ~64 m tile, so the 7 m grain tile stops being visible as
##     a repeating pattern out to the horizon.
##  3. WHEEL-POLISHED LANES — the detail that says "cars drive here". Computed
##     ANALYTICALLY from the street grid, not painted: downtown is a regular
##     lattice (greybox_city.gd:22-27, BLOCK 60 + STREET 26 = 86 m pitch), so
##     the shader can derive distance-from-centreline in both axes and lay
##     burnished wheel paths down every lane. At an intersection both axes fire
##     and the tracks cross — which is what an intersection actually looks like.
##  4. WET RESPONSE — wired to the storm machine that already exists. The grip
##     value has been there since M16 (`sky_weather.gd:_update_grip`); the LOOK
##     never was. Wet asphalt darkens (water fills the pores and kills diffuse
##     scatter), goes specular, and pools into puddles at the gutter — where a
##     crowned road actually drains — which then mirror the sky.
const ROAD_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// --- the two samples. There are no others in this shader. -------------------
// ANISOTROPIC is not a nicety here, it is the fix for a specific artifact. A
// road is viewed at extreme grazing angles almost all the time, so the UV
// derivative along the view is enormous while the one across it is tiny.
// Isotropic mipmapping picks its level from the LARGER derivative, over-blurs
// the whole footprint, and the correlated remainder of the grain flows into
// smooth rolling ripples — the near field photographed like wet fabric. The
// texture data was never the problem; the sampler was.
// surf: R micro-albedo grain | G,B micro-normal XZ | A porosity (grime + wet)
uniform sampler2D surf_tex : filter_linear_mipmap_anisotropic, repeat_enable;
// macro: R repave slab | G drainage height | B oil/grime | A seams
uniform sampler2D macro_tex : filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 base_tint : source_color = vec3(0.170, 0.170, 0.180);
uniform vec3 wet_tint : source_color = vec3(0.055, 0.060, 0.070);
uniform float fine_meters = 7.0;      // world size of the grain tile
uniform float macro_meters = 64.0;    // world size of the variation tile
uniform float bump_strength : hint_range(0.0, 3.0) = 1.0;
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float grain_gain : hint_range(0.0, 2.0) = 1.0;
uniform float macro_gain : hint_range(0.0, 1.0) = 0.35;
uniform float grime_gain : hint_range(0.0, 1.0) = 0.45;

// GLOBAL, not per-material. sky_weather writes this once per physics tick and
// every road surface in the city sees it — no registry of live materials to
// walk, and more importantly no static array holding strong references to
// ShaderMaterials for the life of the process (that array leaked 6 ObjectDB
// instances at exit, intermittently, and the gate allows 6).
global uniform float road_wetness;

// --- street lattice (downtown only; see grid_rect) --------------------------
uniform vec4 grid_rect = vec4(100.0, 40.0, 790.0, 566.0);  // x0 z0 x1 z1
uniform vec2 grid_origin = vec2(193.0, 133.0);  // one street-centreline crossing
uniform float grid_pitch = 86.0;                // BLOCK 60 + STREET 26
uniform float street_half = 13.0;               // STREET * 0.5
uniform float lane_width = 3.5;
uniform float track_offset = 0.92;              // wheel path off the lane centre
uniform float polish_gain : hint_range(0.0, 1.0) = 0.55;

// Distance from the nearest centreline of a lattice with this pitch.
float centre_dist(float w, float origin, float pitch) {
	return abs(fract((w - origin) / pitch + 0.5) - 0.5) * pitch;
}

// Burnished wheel paths for ONE street axis. `d` is the across-street distance
// from that street's centreline. Lanes sit on a `lane_width` pitch; tyres ride
// `track_offset` either side of each lane centre. Folding the two wheels of a
// lane onto one abs() is deliberate — it is half the instructions and no eye
// can tell the near track from the far one.
float wheel_tracks(float d) {
	float on_street = 1.0 - smoothstep(street_half - 2.5, street_half, d);
	float from_lane = abs(fract(d / lane_width) - 0.5) * lane_width;
	// Wide, soft falloff on purpose. A tight band puts a hard-edged stripe every
	// 1.75 m and the road photographs as corduroy — ploughed furrows, not tyre
	// polish. Broad overlapping bands merge into the ribbons a real lane has.
	float track = 1.0 - smoothstep(0.20, 1.02, abs(from_lane - track_offset));
	return track * on_street;
}

void fragment() {
	// World position and world geometric normal. Doing this by matrix rather
	// than by UV is what lets ONE material paint the flat street bed, the
	// rotated freeway ramps and the levee banks with no UV authoring and no
	// tangents on the mesh (every ground mesh here is a shared BoxMesh from
	// greybox_city.gd:_shared_mesh — none of them have meaningful UVs).
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec4 surf = texture(surf_tex, wp.xz / fine_meters);
	vec4 macro = texture(macro_tex, wp.xz / macro_meters);

	// --- street lattice ----------------------------------------------------
	vec2 edge = min(wp.xz - grid_rect.xy, grid_rect.zw - wp.xz);
	float in_grid = smoothstep(0.0, 10.0, min(edge.x, edge.y));
	float dx = centre_dist(wp.x, grid_origin.x, grid_pitch);  // across N-S streets
	float dz = centre_dist(wp.z, grid_origin.y, grid_pitch);  // across E-W streets
	float polish = max(wheel_tracks(dx), wheel_tracks(dz)) * in_grid;
	// Distance from the crown of whichever street this is. Small at a
	// centreline, ~street_half at the kerb, and small again at intersections
	// where both axes are near zero.
	float from_crown = min(min(dx, dz), street_half) / street_half;

	// --- albedo ------------------------------------------------------------
	float grain = mix(1.0, surf.r * 2.0, grain_gain);
	float slab = mix(1.0, 0.82 + 0.36 * macro.r, macro_gain);   // repave patches
	vec3 alb = base_tint * grain * slab;
	// Oil and rubber collect on the crown and in the lanes, not at the kerb.
	float oil = macro.b * grime_gain * (1.0 - from_crown) * in_grid;
	alb *= 1.0 - 0.35 * oil;
	// Polished lanes are darker and smoother — aggregate worn flush, bitumen
	// brought to the surface. This is why real lanes photograph as ribbons.
	alb *= 1.0 - polish_gain * polish * 0.42;
	// Seams and cracks are a thin dark line, never a colour.
	alb *= 1.0 - 0.45 * macro.a;

	// --- micro normal ------------------------------------------------------
	// Tangent frame built from the geometric normal, so this works on the flat
	// street bed AND on the rotated ramp boxes without touching the meshes.
	vec3 up_ref = abs(wn.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tan_z = normalize(cross(up_ref, wn));
	vec3 tan_x = cross(wn, tan_z);
	// Polished lanes are physically SMOOTHER: knock the micro relief down where
	// the tyres have worn it flat.
	float relief = bump_strength * (1.0 - 0.65 * polish);
	vec2 nxz = (surf.gb - 0.5) * 2.0 * relief;
	vec3 pert = normalize(tan_x * nxz.x + tan_z * nxz.y + wn);

	// --- wet response ------------------------------------------------------
	// M23: WATER FINDS THE LOW GROUND FIRST. The shipped version ramped `damp`
	// straight off `road_wetness`, so the crown of the road and the bottom of
	// the gutter went wet at the same instant and the whole street changed
	// state as one sheet. Rain does not do that. `macro.g` is the drainage
	// height, so a hollow needs far less water to go glossy than a crown does:
	// `need` is how much wetness this texel requires before it reads wet at
	// all. Under SSR this is the entire difference between "it rained" and "a
	// dark shiny plane" — reflections appear in the hollows, spread up the
	// camber, and drain back down in that order.
	float low = smoothstep(0.62, 0.20, macro.g);       // 1 in the hollows
	float gutter = mix(0.55, 1.35, from_crown);
	float need = mix(0.52, 0.06, low * gutter);
	float damp = smoothstep(need * 0.30, need + 0.34, road_wetness)
		* mix(0.55, 1.0, surf.a);
	float puddle = clamp(low * gutter
		* smoothstep(need + 0.10, need + 0.52, road_wetness), 0.0, 1.0);
	alb = mix(alb, wet_tint, clamp(damp * 0.72 + puddle * 0.28, 0.0, 1.0));
	// Standing water is a flat mirror: flatten the micro relief inside puddles.
	pert = normalize(mix(pert, wn, puddle * 0.92));

	// --- roughness, WITH VARIATION -----------------------------------------
	// The shipped road carried ONE roughness number modified by wetness. A
	// uniform roughness is the loudest plastic tell there is under SSR and GI,
	// because every pixel returns the same lobe width and the surface has no
	// history. All three terms below come out of channels this shader ALREADY
	// samples — the variation costs zero extra texture reads.
	//  * surf.a (porosity): an open, voided matrix scatters; a polished
	//    aggregate crown does not.
	//  * macro.r (repave slabs): a patch cut in last year and a patch from
	//    1994 do not weather alike, and the join between them is the single
	//    most recognisable thing about a real city street.
	//  * oil: a rubber-and-oil film is smoother than the aggregate under it.
	float rough = dry_roughness;
	rough *= 0.88 + 0.20 * surf.a;
	rough *= 0.86 + 0.24 * macro.r;
	rough = mix(rough, rough * 0.74, oil);             // oil/rubber film
	rough = mix(rough, rough * 0.74, polish);          // burnished lanes
	rough = mix(rough, 0.30, damp);                    // sheen
	rough = mix(rough, 0.035, puddle);                 // standing water

	ALBEDO = alb * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(pert, 0.0)).xyz);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	// Dielectric water sits near 0.5 reflectance; dry aggregate well below it.
	SPECULAR = mix(0.32, 0.62, max(damp, puddle));
}
"""


# =============================== GLAZING =====================================
## FRESNEL GLASS. This replaces the last live instance of the metallic-glass
## hack the vehicle builder already retired in D-039 (vehicle_body_builder.gd:
## 60-64: "metallic 0.35 on a low-roughness surface with no reflection probe in
## the scene renders as a flat sample of the bright Texas sky — i.e. a painted
## panel"). Cars were fixed then. BUILDINGS were not: storefront glass still
## runs metallic 0.22 (city_textures.gd:170), tower glass 0.1, the corporate
## curtain wall 0.42 with metallic_specular 0.72.
##
## Why metallic is the wrong knob for glass. In a PBR renderer `metallic` means
## "this surface has no diffuse and its colour IS its reflection". Glass is a
## DIELECTRIC: it has a weak, constant 4% reflection head-on that climbs to a
## total mirror at grazing incidence. That angular ramp — Schlick's fresnel — is
## the entire visual signature of glass, and `metallic` throws it away and
## returns a flat, angle-independent sample of whatever the radiance cubemap
## holds. On a bright Texas noon that is a uniform pale wash on every pane in
## the city, and it is most of why the towers read as flat-lit boxes.
##
## Costs nothing: no texture sample, one dot product and one pow.
const GLASS_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec4 glass_color : source_color = vec4(0.13, 0.15, 0.17, 1.0);
uniform vec4 reflect_tint : source_color = vec4(0.62, 0.70, 0.80, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.34;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float fresnel_power : hint_range(1.0, 8.0) = 5.0;
uniform float f0 : hint_range(0.0, 0.5) = 0.045;   // dielectric, n ~ 1.5
uniform vec4 interior_glow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float glow_energy : hint_range(0.0, 4.0) = 0.0;

// --- INTERIOR MAPPING (M23) --------------------------------------------------
// The classic cube-parallax fake room. A storefront pane used to be a flat
// dark tint with a constant warm glow behind it, which is why every shop in
// the city read as the same painted rectangle: there was nothing BEHIND the
// glass, so the eye got no parallax cue and the pane collapsed onto the wall.
// This traces the view ray into a virtual box behind each pane and shades
// whichever inside face it hits. It costs no texture sample and no loop — one
// ray/box intersection is three divides and two mins — and it produces the one
// cue a painted glow never can: the room SHIFTS as you walk past it.
uniform float room_w = 3.0;         // metres per fake room across the frontage
uniform float room_h = 3.2;         // metres per fake room up the wall
uniform float room_depth = 2.6;     // how far back the box goes
uniform float interior_gain : hint_range(0.0, 2.0) = 0.0;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.55;
// Written once per tick by the night driver; 0 = noon, 1 = full night. If
// nothing ever writes it the value is 0.0 and the interiors sit at their
// daylight level, which is exactly the behaviour this replaced.
global uniform float night_level;

// The sin-hash breaks down on world coordinates. `dot(cell, (127.1, 311.7))`
// with a cell index near 580 lands around 10^5, and sin() of that in fp32 has
// so little mantissa left that neighbouring cells return correlated values —
// which is exactly what the first plate at `plaza` showed: an entire block of
// shopfronts with the identical room in every pane. Folding the cell into a
// 128-cell torus first keeps the argument small; 128 cells at 3 m is 384 m of
// frontage before the pattern repeats, and no sightline in this city sees
// that much shopfront at once.
float ihash(vec2 p) {
	vec2 q = mod(p, 128.0);
	return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Schlick. NORMAL and VIEW are both view-space in a Godot fragment shader,
	// so this needs no matrices.
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = f0 + (1.0 - f0) * pow(1.0 - ndv, fresnel_power);

	vec3 base = glass_color.rgb;
	vec3 room_emit = vec3(0.0);

	if (interior_gain > 0.0) {
		// Pane-local frame from the WORLD normal, so one material works on all
		// four faces of a podium with no UV authoring — the same trick the road
		// shader uses to paint rotated ramps.
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 up_ref = abs(wn.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 tx = normalize(cross(up_ref, wn));
		vec3 ty = cross(wn, tx);
		vec2 uv = vec2(dot(wp, tx) / room_w, dot(wp, ty) / room_h);
		vec2 cell = floor(uv);
		vec2 f = fract(uv);
		// View direction into the wall, in pane space. d.z is negative when the
		// camera is in front of the pane, which is the only case that matters.
		vec3 vdir = normalize(wp - INV_VIEW_MATRIX[3].xyz);
		vec3 d = vec3(dot(vdir, tx) / room_w, dot(vdir, ty) / room_h,
			dot(vdir, wn) / room_depth);
		d += vec3(equal(d, vec3(0.0))) * 1e-4;   // no divide by an axis-aligned ray
		// Slab intersection against the unit box behind the pane.
		vec3 far_c = vec3(step(0.0, d.x), step(0.0, d.y), -1.0);
		vec3 t3 = (far_c - vec3(f, 0.0)) / d;
		float t = min(t3.z, min(abs(t3.x), abs(t3.y)));
		vec3 hit = vec3(f, 0.0) + d * t;

		// One room per cell: warm tungsten or cool fluorescent, never both.
		float r1 = ihash(cell);
		float r2 = ihash(cell + vec2(41.7, 13.1));
		vec3 warm = vec3(1.00, 0.72, 0.40);
		vec3 cool = vec3(0.72, 0.84, 1.00);
		// Wide value spread on purpose: a row of shopfronts where every room is
		// the same brightness is a row of stickers. 0.30-1.00 is a shuttered
		// unit next to a lit one next to a dim one.
		vec3 room = mix(warm, cool, step(0.62, r2)) * (0.30 + 0.70 * r1);
		// Shade by which face was hit. The light is on the ceiling, so the
		// ceiling is brightest, the back wall mid and the floor darkest — that
		// vertical gradient is most of what makes the box read as a ROOM.
		float depth_k = clamp(-hit.z, 0.0, 1.0);
		float face = 0.55 + 0.45 * hit.y;                 // floor dark, ceiling lit
		float shade = face * mix(1.0, 0.42, depth_k);      // falls off with depth
		// A dark bar across the bottom: the counter/shelf line every shop has.
		shade *= 1.0 - 0.45 * (1.0 - smoothstep(0.10, 0.26, hit.y));
		vec3 interior = room * shade;

		// Only `lit_fraction` of the rooms have their lights on, and the ones
		// that do come up on the night ramp. Peak stays under the project's
		// 1.05 glow threshold on purpose (D-032): a shop window is warm, not a
		// bloom source.
		float on = step(1.0 - lit_fraction, ihash(cell + vec2(7.3, 91.7)));
		// 0.09 by day: a shop window in Texas noon is DARKER than the wall
		// around it, and the interior lights barely register. The old constant
		// 0.84 glow was a night value burning all day.
		float lvl = mix(0.09, 1.0, clamp(night_level, 0.0, 1.0));
		room_emit = interior * interior_gain * on * lvl * 0.86;
		// A dark room is dark in ALBEDO too, not merely unlit — otherwise every
		// shuttered unit still reads as a pale panel in daylight.
		base = mix(base, interior * mix(0.16, 0.55, on), 0.88);
	}

	ALBEDO = mix(base, reflect_tint.rgb, fres);
	// The physical part: glass is see-through head-on and a mirror edge-on.
	// Head-on transmission is preserved deliberately — D-039's whole point was
	// that you must be able to see the cabin/interior behind the pane.
	ALPHA = clamp(base_alpha + (1.0 - base_alpha) * fres, 0.0, 1.0);
	ROUGHNESS = glass_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = interior_glow.rgb * glow_energy + room_emit;
}
"""


# ============================== CAR PAINT ====================================
## Automotive two-stage paint: a pigmented base coat with suspended metallic
## flake, under a clear lacquer. The clear coat is a SECOND specular lobe with
## its own (much lower) roughness, which is why a real car has a tight, bright
## highlight riding on top of a broad soft one. `CLEARCOAT` is a first-class
## Forward+ output in Godot 4 — probed on this exact build before use.
##
## The flake is a cell hash on UV, not a texture: body panels here are boxes
## from a shared mesh cache, so a screen-stable procedural is both cheaper and
## better-behaved than a sample would be.
const PAINT_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.6, 0.1, 0.1, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.38;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.15;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.65;
uniform float clearcoat_rough : hint_range(0.0, 1.0) = 0.045;
uniform float flake_gain : hint_range(0.0, 1.0) = 0.30;
uniform float flake_scale = 220.0;
uniform float fresnel_gain : hint_range(0.0, 1.0) = 0.35;
// ORANGE PEEL (M23). Every sprayed panel that has ever left a factory has it:
// the clear coat levels under gravity into a shallow, quasi-random ripple a
// centimetre or two across. It is invisible in albedo and unmistakable in a
// REFLECTION, which is exactly why it matters now — the moment SSR puts a real
// skyline in a car's flank, a perfectly flat panel reads as chrome vinyl. The
// flake sparkle above is high-frequency and stochastic; this is low-frequency
// and continuous, and the two do different jobs.
//
// Three incommensurate wave pairs rather than a noise texture: the derivative
// is analytic (a cosine), so the normal perturbation is exact instead of a
// finite difference costing three more hashes per pixel, and the doctrine
// forbids the texture anyway.
uniform float peel_gain : hint_range(0.0, 0.2) = 0.045;
uniform float peel_scale = 26.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 5.0);

	// Metallic flake: one hash per cell, tilted into the specular lobe so it
	// sparkles with view angle instead of being a static speckle texture.
	vec2 cell = floor(UV * flake_scale);
	float h = hash21(cell);
	float h2 = hash21(cell + 17.3);
	float sparkle = smoothstep(0.86, 1.0, h) * flake_gain;

	vec3 n = normalize(NORMAL);
	// Perturb only where a flake actually is; elsewhere the panel stays glassy.
	n = normalize(n + vec3(h - 0.5, h2 - 0.5, 0.0) * sparkle * 1.6);

	// Orange peel. A = the height field; dA/du, dA/dv are its exact slopes.
	vec2 p = UV * peel_scale;
	float du = 1.00 * cos(p.x * 1.00 + p.y * 0.31)
		+ 0.62 * 0.73 * cos(p.x * 0.73 - p.y * 1.19)
		+ 0.38 * 1.61 * cos(p.x * 1.61 + p.y * 0.87);
	float dv = 0.31 * cos(p.x * 1.00 + p.y * 0.31)
		- 0.62 * 1.19 * cos(p.x * 0.73 - p.y * 1.19)
		+ 0.38 * 0.87 * cos(p.x * 1.61 + p.y * 0.87);
	n = normalize(n + vec3(-du, -dv, 0.0) * peel_gain);

	// Base coat darkens slightly at grazing angles before the clear coat's
	// fresnel takes over — the "depth" of a good paint job.
	vec3 base = paint_color.rgb * (1.0 - 0.18 * fres);
	ALBEDO = base + vec3(sparkle * 0.55);
	NORMAL = n;
	// THE CLEARCOAT WAS BEING FLATTENED, and this is the fix the mandate asked
	// for. Godot's CLEARCOAT adds a second specular lobe, but the PRIMARY lobe
	// — and, critically, the roughness SSR fades its reflection by — is still
	// ROUGHNESS. The vehicle builder passes 0.34 for standard paint, which is
	// a correct number for a BASE COAT and a wrong one for the outside of a
	// clear-coated panel: at 0.34 screen-space reflection is blurred to nothing
	// and every car in the city returns a flat sample of the sky. What the eye
	// actually sees is the clear coat, so the surface the renderer is handed is
	// the base roughness pulled toward the clear coat's, in proportion to how
	// much clear coat there is. Standard paint 0.34 -> 0.223; Slab candy
	// (clearcoat 0.95) 0.14 -> 0.075. Callers keep their numbers and their
	// meaning; only the interpretation is now physically right.
	ROUGHNESS = mix(base_roughness, clearcoat_rough, clearcoat_amount * 0.72);
	METALLIC = clamp(base_metallic + sparkle * 0.5, 0.0, 1.0);
	SPECULAR = 0.5 + fresnel_gain * fres * 0.5;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_rough;
}
"""


# ================================ SKIN =======================================
## Cheap wrap/subsurface approximation. NOT Godot's screen-space SSS: that is a
## full-screen pass whose cost lands on the whole frame the moment ONE material
## in view enables it, and this city can have 30+ pedestrians on screen. The
## same read is available for free from two engine-side terms:
##
##  BACKLIGHT — light arriving from BEHIND the surface bleeds through. This is
##    the actual "wrap": it fills the terminator so the shadow side of a nose or
##    a cheek falls off softly and warmly instead of clipping to ambient. A face
##    lit by one hard directional with no wrap is exactly what "painted plastic"
##    means, and this is the term that fixes it.
##  RIM — the peach-fuzz halo at grazing angles, tinted to the light.
##
## Both live inside Godot's own light loop, so a custom light() function — which
## would mean reimplementing the entire BRDF and re-testing it against the 492
## suburb lights and the hospital apron — is not needed.
##
## The curvature term is the one thing StandardMaterial3D cannot do: thin, high-
## curvature parts of a face (nose, ear rims, lips) transmit more red because
## there is less flesh for the light to cross. That is what stops a head reading
## as a painted egg, and it is one screen-space derivative pair, no samples.
const SKIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 skin_color : source_color = vec4(0.55, 0.38, 0.26, 1.0);
uniform vec4 blood_tint : source_color = vec4(0.62, 0.20, 0.16, 1.0);
uniform float skin_roughness : hint_range(0.0, 1.0) = 0.72;
// Deliberately modest. `fwidth(NORMAL)` measures how fast the normal turns per
// pixel, which on a SMOOTH head is anatomy — but these heads are low-poly, so
// it also spikes along every facet boundary. Cranked up it finds the
// tessellation instead of the nose and the jaw photographs orange. The term is
// worth keeping small; BACKLIGHT below is doing most of the real work.
uniform float curvature_gain : hint_range(0.0, 2.0) = 0.42;
uniform float backlight_gain : hint_range(0.0, 1.0) = 0.22;
uniform float rim_gain : hint_range(0.0, 1.0) = 0.30;
uniform float oil_gain : hint_range(0.0, 1.0) = 0.28;
uniform bool use_vertex_color = false;
// M24: a triplanar pore normal, sampled in OBJECT space scaled to metres, so
// it is rigid on the part it sits on (the head turns, the pores turn with it)
// and the same size on a 0.2 m head shell and a 0.04 m eyelid ball.
uniform sampler2D micro_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float micro_tiles = 16.6667;
uniform float micro_bump : hint_range(0.0, 2.0) = 0.6;
uniform float mottle_gain : hint_range(0.0, 0.5) = 0.08;

varying vec3 v_pobj;
varying vec3 v_nobj;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	v_pobj = VERTEX * sc;
	v_nobj = NORMAL;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 no = normalize(v_nobj);
	vec3 w3 = no * no;
	w3 /= (w3.x + w3.y + w3.z);
	vec3 pp = v_pobj * micro_tiles;
	vec4 tx = texture(micro_tex, pp.zy);
	vec4 ty = texture(micro_tex, pp.xz);
	vec4 tz = texture(micro_tex, pp.xy);
	vec3 dn = w3.x * vec3(0.0, tx.y * 2.0 - 1.0, tx.x * 2.0 - 1.0)
		+ w3.y * vec3(ty.x * 2.0 - 1.0, 0.0, ty.y * 2.0 - 1.0)
		+ w3.z * vec3(tz.x * 2.0 - 1.0, tz.y * 2.0 - 1.0, 0.0);
	float mottle = w3.x * tx.a + w3.y * ty.a + w3.z * tz.a;
	// Screen-space curvature: how fast the normal is turning under this pixel.
	// High on a nose bridge, an ear rim, a lip edge; ~0 on a flat cheek.
	float curv = clamp(length(fwidth(n)) * 14.0, 0.0, 1.0) * curvature_gain;

	vec3 base = skin_color.rgb;
	if (use_vertex_color) {
		// The head shell bakes nose/lips/brow relief into vertex colour as a
		// MULTIPLIER (character_factory.gd:2252-2256 — a ratio, never a colour,
		// so the D-018 sRGB instance-colour trap does not apply).
		base *= COLOR.rgb;
	}
	// Thin, curved flesh goes red. This is the whole subsurface read in one
	// mix, and it costs one fwidth().
	base *= mix(1.0 - mottle_gain, 1.0 + mottle_gain, mottle);
	ALBEDO = mix(base, base * blood_tint.rgb * 1.7, curv * 0.38);

	ROUGHNESS = skin_roughness;
	METALLIC = 0.0;
	// Skin is a weak dielectric with a broad sheen, never a highlight dot. Oil
	// concentrates on the same high points the curvature term found.
	SPECULAR = 0.22 + oil_gain * curv * 0.5;
	// Object axes in view space, each normalised: MODEL_NORMAL_MATRIX carries
	// the part's inverse scale, and on a 0.02 m ear it multiplied the delta by
	// fifty — the gold speckle on every eyelid and ear in collar7/face.png.
	mat3 mv = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX;
	vec3 dv = normalize(mv[0]) * dn.x + normalize(mv[1]) * dn.y + normalize(mv[2]) * dn.z;
	NORMAL = normalize(n + dv * micro_bump);

	// Engine-side wrap. BACKLIGHT is warmed toward blood so light coming
	// through an ear or a nostril arrives red, which is what it does.
	BACKLIGHT = mix(base, blood_tint.rgb, 0.55) * backlight_gain;
	RIM = rim_gain;
	RIM_TINT = 0.35;
}
"""


# ========================= COMPILED SHADER CACHE =============================
## One `Shader` per source, process-lifetime. Godot batches by shader, so every
## road surface in the city shares one compiled program and one pipeline state
## no matter how many ShaderMaterials point at it.
static var _shaders: Dictionary = {}
## Road/pavement materials, cached by kind. Sharing matters twice over: the
## three asphalt call sites (greybox_city.gd, city_dressing.gd x2) used to build
## three identical materials and three identical textures, which is three draw
## batches for what is visually one surface.
static var _road_cache: Dictionary = {}
static var _wet_registered := false


static func _shader(key: String, src: String) -> Shader:
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = src
		_shaders[key] = sh
	return _shaders[key]


## Rain drives every road surface at once, through one global shader parameter.
## Called from sky_weather's storm tick. A no-op under `--gfx-legacy`, where the
## parameter is never registered and no shader reads it.
static func set_wetness(w: float) -> void:
	if not _wet_registered:
		return
	RenderingServer.global_shader_parameter_set("road_wetness", clampf(w, 0.0, 1.0))


## Registered once, lazily, and BEFORE the first road Shader is compiled — a
## shader referencing a global that does not exist yet logs an error at compile
## time. The `_wet_registered` flag is the whole guard: do NOT reach for
## `global_shader_parameter_get_list()` to check first, because it is an
## editor-only call and at runtime it logs "This function should never be used
## outside the editor", which is an error line, which fails the headless gate.
static func _register_wetness() -> void:
	if _wet_registered:
		return
	_wet_registered = true
	RenderingServer.global_shader_parameter_add("road_wetness",
		RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


# ---------------------------- THE FORKS --------------------------------------
## These are the swap points. Every caller that used to say
## `TEX.asphalt_material()` now says `SHD.asphalt_material()` and gets either
## arm depending on `--gfx-legacy`; nothing else at any call site changed. The
## legacy arm returns the ORIGINAL function untouched, which is what makes the
## A/B honest — it is not a reimplementation of the old look, it IS the old look.

static func asphalt_material() -> Material:
	if legacy():
		return TEX.asphalt_material()
	return road_material("asphalt")


static func concrete_material() -> Material:
	if legacy():
		return TEX.concrete_material()
	return road_material("concrete")


## Storefront/podium glazing. Legacy arm is `city_textures.storefront_glass_material`
## verbatim, metallic hack and all.
static func storefront_glass(lit: bool) -> Material:
	if legacy():
		return TEX.storefront_glass_material(lit)
	# THE GLASS DECISION, storefront half (M23). This one stays TRANSPARENT and
	# it stops faking depth with a dark tint: it now has an actual interior.
	#
	# The old pane was alpha 0.42 over a solid podium wall — 58% of every shop
	# window was the brick behind it, which is why the D-013 note about glass
	# "reading as a hole" keeps coming back no matter what the tint is. There is
	# nothing to see through it, so transmission was spending budget on nothing.
	# With interior mapping the pane HAS something behind it, so the alpha goes
	# up to 0.86 (the room becomes the content, the fresnel edge stays a mirror)
	# and the warm constant glow is replaced by rooms that are individually lit
	# or dark, warm or cool, and shift with parallax as the player walks past.
	#
	# Alpha 0.86 keeps this material in the TRANSPARENT pass, so it is not an
	# SSR receiver. That is the right trade at street range: at 4 m from a shop
	# window the interior is what a player looks at, and the fresnel rim still
	# carries the sky. The opaque/reflective decision is made the other way for
	# curtain-wall towers (city_textures.tower_material), where the reflection
	# IS the content and nobody is looking in.
	#
	# THE CONSTANT GLOW IS GONE, and that was the whole point. Keeping M14's
	# flat `interior_glow` alongside the rooms was measured at `plaza` and it
	# washed every pane back to one solid orange rectangle — the fake room was
	# there and a 0.46 constant emission was painted over the top of it. The
	# rooms now carry the light on their own, per cell, which is why some
	# windows are dark and no two lit ones match.
	# alpha 0.95, not 0.86. At 0.86 the 14% that transmits is the PODIUM BRICK
	# directly behind the pane, and once the unlit rooms were darkened the brick
	# coursing became legible THROUGH the shop windows at `plaza` — the D-013
	# "reads as a hole" failure in a new costume. The room is the content now,
	# so the pane keeps 5% for a hint of transmission and lets fresnel take it
	# to a mirror at the edges.
	var m := glass_material(Color(0.10, 0.12, 0.14), 0.95, 0.05,
		Color.BLACK, 0.0)
	m.set_shader_parameter("interior_gain", 1.35 if lit else 0.85)
	m.set_shader_parameter("lit_fraction", 0.66 if lit else 0.28)
	m.set_shader_parameter("room_w", 3.0)
	m.set_shader_parameter("room_h", 3.2)
	m.set_shader_parameter("room_depth", 2.6)
	return m


## Road/pavement material. `kind` selects the surface recipe.
static func road_material(kind: String) -> ShaderMaterial:
	if _road_cache.has(kind):
		return _road_cache[kind]
	_register_wetness()
	var m := ShaderMaterial.new()
	m.shader = _shader("road", ROAD_SHADER)
	m.set_shader_parameter("surf_tex", TEX.road_surface_texture(kind))
	m.set_shader_parameter("macro_tex", TEX.road_macro_texture(kind))
	if kind == "concrete":
		# Sidewalks, the freeway deck, the floodway floor. Pale, broom-finished,
		# far less rubber on it, and it never polishes into lanes the way a
		# bitumen surface does.
		m.set_shader_parameter("base_tint", Color(0.480, 0.470, 0.445))
		m.set_shader_parameter("wet_tint", Color(0.230, 0.230, 0.225))
		m.set_shader_parameter("fine_meters", 4.5)
		m.set_shader_parameter("macro_meters", 47.0)
		m.set_shader_parameter("dry_roughness", 0.90)
		m.set_shader_parameter("bump_strength", 0.40)
		m.set_shader_parameter("grain_gain", 0.85)
		m.set_shader_parameter("macro_gain", 0.20)
		m.set_shader_parameter("grime_gain", 0.30)
		m.set_shader_parameter("polish_gain", 0.16)
	else:
		m.set_shader_parameter("base_tint", Color(0.170, 0.170, 0.180))
		m.set_shader_parameter("wet_tint", Color(0.055, 0.060, 0.070))
		m.set_shader_parameter("fine_meters", 7.0)
		m.set_shader_parameter("macro_meters", 64.0)
		m.set_shader_parameter("dry_roughness", 0.95)
		m.set_shader_parameter("bump_strength", 0.42)
		m.set_shader_parameter("grain_gain", 1.0)
		m.set_shader_parameter("macro_gain", 0.24)
		m.set_shader_parameter("grime_gain", 0.34)
		m.set_shader_parameter("polish_gain", 0.55)
	_road_cache[kind] = m
	return m


## Fresnel glazing. `lit` adds the constant warm interior that storefront glass
## has carried since M14 — kept UNDER the 1.05 HDR bloom threshold on purpose
## (main.gd:196; city_textures.gd:161-165 documents why 0.84 and not more).
static func glass_material(color: Color, alpha: float, rough: float,
		lit_color := Color.BLACK, lit_energy := 0.0) -> ShaderMaterial:
	_register_night()
	var m := ShaderMaterial.new()
	m.shader = _shader("glass", GLASS_SHADER)
	m.set_shader_parameter("glass_color", color)
	m.set_shader_parameter("base_alpha", alpha)
	m.set_shader_parameter("glass_roughness", rough)
	m.set_shader_parameter("interior_glow", lit_color)
	m.set_shader_parameter("glow_energy", lit_energy)
	return m


static func paint_material(c: Color, rough: float, metal: float,
		clearcoat: float, flake: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("paint", PAINT_SHADER)
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("base_roughness", rough)
	m.set_shader_parameter("base_metallic", metal)
	m.set_shader_parameter("clearcoat_amount", clearcoat)
	m.set_shader_parameter("flake_gain", flake)
	return m


## M24. THE SHARED CHARACTER SURFACE (skinned body + garment shells). The
## palette (UV: zone column, height row) is still the whole wardrobe; this adds
## what a palette cannot carry: a surface. A class channel in the metallic
## texture's G says skin / cloth / hard per row, and the shader tiles a pore
## normal (with mottle in its alpha) on skin and a crumple-and-thread normal
## (fold shading in alpha) on cloth, over the bind-pose micro UV in UV2. The
## tangent frame is measured per pixel from screen derivatives, so the bake
## stores none and any deformation is correct by construction. Skin rows get
## the head's own subsurface terms (curvature blood, backlight, rim) so the
## neck no longer changes shading where the factory head meets the body.
const PALETTE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D pal_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D met_tex : filter_linear, repeat_disable;
uniform sampler2D skin_micro : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloth_micro : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 blood_tint : source_color = vec4(0.62, 0.20, 0.16, 1.0);
uniform float skin_bump : hint_range(0.0, 2.0) = 0.55;
uniform float cloth_bump : hint_range(0.0, 2.0) = 0.30;
uniform float mottle_gain : hint_range(0.0, 0.5) = 0.08;
uniform float fold_shade : hint_range(0.0, 0.5) = 0.04;
// Lower than the head's 0.42: the hands are small geometry whose normal turns
// fast per pixel, so the curvature term saturated and painted them orange.
uniform float curvature_gain : hint_range(0.0, 2.0) = 0.18;
uniform float backlight_gain : hint_range(0.0, 1.0) = 0.22;
uniform float rim_gain : hint_range(0.0, 1.0) = 0.30;
uniform float oil_gain : hint_range(0.0, 1.0) = 0.28;

varying vec2 v_muv;

void vertex() {
	v_muv = UV2;
}

// Tangent frame from screen-space derivatives (Schueler). Exact for any UV
// layout on any deformation because it is measured on the rendered surface.
mat3 cotangent_frame(vec3 n, vec3 p, vec2 uv) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);
	vec3 dp2perp = cross(dp2, n);
	vec3 dp1perp = cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(dot(t, t), dot(b, b)) + 0.000000000001);
	return mat3(t * invmax, b * invmax, n);
}

void fragment() {
	vec4 pal = texture(pal_tex, UV);
	vec2 mc = texture(met_tex, UV).rg;
	float cls = mc.g;
	float is_skin = 1.0 - smoothstep(0.15, 0.35, cls);
	float is_cloth = smoothstep(0.15, 0.35, cls) * (1.0 - smoothstep(0.65, 0.85, cls));
	vec3 n = normalize(NORMAL);
	vec3 base = pal.rgb;

	vec4 sk = texture(skin_micro, v_muv * 1.3333333);
	vec4 cl = texture(cloth_micro, v_muv);
	vec3 nts = vec3(0.0, 0.0, 1.0);
	nts.xy += (sk.xy * 2.0 - 1.0) * skin_bump * is_skin;
	nts.xy += (cl.xy * 2.0 - 1.0) * cloth_bump * is_cloth;
	nts = normalize(nts);
	mat3 tbn = cotangent_frame(n, VERTEX, v_muv);
	vec3 nn = normalize(tbn * nts);

	float curv = clamp(length(fwidth(n)) * 14.0, 0.0, 1.0) * curvature_gain;
	base *= mix(1.0, mix(1.0 - mottle_gain, 1.0 + mottle_gain, sk.a), is_skin);
	base *= mix(1.0, mix(1.0 - fold_shade, 1.0, cl.a), is_cloth);
	ALBEDO = mix(base, base * blood_tint.rgb * 1.7, curv * 0.38 * is_skin);
	ROUGHNESS = pal.a;
	METALLIC = mc.r;
	SPECULAR = mix(0.5, 0.22 + oil_gain * curv * 0.5, is_skin);
	NORMAL = nn;
	BACKLIGHT = mix(base, blood_tint.rgb, 0.55) * backlight_gain * is_skin;
	RIM = rim_gain * is_skin + 0.04 * is_cloth;
	RIM_TINT = 0.35;
}
"""


static func palette_material(pal_tex: Texture2D, met_tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("palette", PALETTE_SHADER)
	m.set_shader_parameter("pal_tex", pal_tex)
	m.set_shader_parameter("met_tex", met_tex)
	m.set_shader_parameter("skin_micro", TEX.skin_micro_texture())
	m.set_shader_parameter("cloth_micro", TEX.cloth_micro_texture())
	return m


static func skin_material(c: Color, rough: float, vertex_color: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("skin", SKIN_SHADER)
	m.set_shader_parameter("skin_color", c)
	m.set_shader_parameter("skin_roughness", rough)
	m.set_shader_parameter("use_vertex_color", vertex_color)
	m.set_shader_parameter("micro_tex", TEX.skin_micro_texture())
	return m


# ============================ VEGETATION WIND ================================
## M23. Nothing in this city has ever moved except vehicles and people. A
## prairie of 11,919 grass cards, 341 live-oak canopies and 4,000-odd bluestem
## tufts standing dead still under a Texas sky is one of the loudest "this is a
## model, not a place" signals in the game, and it costs a vertex shader to fix.
##
## THE MODEL. Sway is a bending BEAM, not a translation: displacement grows as
## the SQUARE of height up the plant, because a cantilever's deflection under a
## uniform load does. That single term is the difference between grass that
## bends and grass that slides sideways — and it is also why TRUNKS DO NOT
## MOVE: at the base, height is 0 and height² is 0, so a trunk mesh whose
## vertices all sit near y=0 in local space is displaced by exactly zero. The
## wind diff measurement in the report leans on that: canopy pixels change,
## trunk pixels must not.
##
## PHASE comes from WORLD position, not from the instance index, so neighbours
## that happen to be adjacent in the MultiMesh buffer do not sway in lockstep,
## and a gust reads as a wave crossing the field rather than the whole prairie
## breathing at once. INSTANCE_CUSTOM is NOT used: these MultiMeshes were built
## by seeded layers this pass is forbidden to re-draw, and `use_custom_data` is
## a buffer-format change, not a material change.
##
## `wind_gust` is a GLOBAL shader parameter for the same reason `road_wetness`
## is: one write per tick from the weather system, no registry of live
## materials, and no static array holding strong references to ShaderMaterials
## for the life of the process (that array leaked 6 ObjectDB at exit in D-030).
## DEFAULT 0.0 = perfectly still, so if nothing ever drives it the game looks
## exactly as it does today and no screenshot in the archive is invalidated.
const WIND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float wind_gust;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float veg_roughness : hint_range(0.0, 1.0) = 1.0;
// Metres of sway at 1 m of local height, at gust 0. Tuned per layer: a grass
// blade whips, a live-oak limb barely moves.
uniform float sway = 0.06;
uniform float sway_gust = 0.10;      // extra metres per unit of wind_gust
uniform float rate = 1.35;           // base oscillation, rad/s
uniform float flutter = 0.0;         // high-frequency edge chatter (cards only)
uniform bool use_vertex_color = true;
// 0 = cantilever (a blade rooted at its own origin, tip moves as height^2).
// 1 = RIGID (the whole mesh translates as one). A live-oak canopy is a blob
// whose local origin is its own CENTRE, not the ground — feeding it the
// cantilever term would shear the crown, top against bottom, which is what a
// tree does not do. A crown sways about a trunk that is not in this mesh, so
// for canopies the correct model is a rigid translation of the whole lobe.
uniform float rigid_mix : hint_range(0.0, 1.0) = 0.0;
// M23 foliage: a leaf-cluster tile sampled triplanar off world position (the
// crowns carry no UVs or tangents), its relief perturbing the world normal.
uniform bool use_leaf = false;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaf_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float leaf_scale = 0.72;       // tiles per metre
uniform float leaf_bump : hint_range(0.0, 2.0) = 0.9;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	// World position of the INSTANCE origin, not of this vertex: every vertex
	// of one plant must share one phase or the plant shears instead of bends.
	vec3 root = MODEL_MATRIX[3].xyz;
	float phase = root.x * 0.37 + root.z * 0.29;
	float t = TIME * rate;
	// Two incommensurate frequencies so the loop never audibly repeats, and a
	// gust term that is a slow travelling wave across the map rather than a
	// global multiplier — 46 m wavelength, walking pace.
	float gust_wave = 0.5 + 0.5 * sin(TIME * 0.55 + root.x * 0.0216 + root.z * 0.0173);
	float amp = sway + sway_gust * wind_gust * gust_wave;
	float bend = sin(t + phase) * 0.72 + sin(t * 1.63 + phase * 2.1) * 0.28;
	// h2: the cantilever term. VERTEX.y is LOCAL, so this is height up the
	// plant. max(0) keeps anything modelled below its own origin still.
	float h = max(VERTEX.y, 0.0);
	float lever = mix(h * h, 1.0, rigid_mix);
	VERTEX.x += bend * amp * lever;
	VERTEX.z += bend * amp * lever * 0.62;
	if (flutter > 0.0) {
		// Leaf chatter: same phase family, four times the rate, scaled by the
		// vertex's own offset from the stem so the centre line stays put.
		float f = sin(t * 4.1 + phase + VERTEX.x * 9.0) * flutter * h;
		VERTEX.x += f * 0.5;
		VERTEX.y -= abs(f) * 0.25;   // a bending blade also gets SHORTER
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = tint.rgb;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	if (use_leaf) {
		vec3 bw = abs(wnrm);
		bw = bw / (bw.x + bw.y + bw.z + 1e-4);
		vec2 uvx = wpos.zy * leaf_scale;
		vec2 uvy = wpos.xz * leaf_scale;
		vec2 uvz = wpos.xy * leaf_scale;
		c *= texture(leaf_tex, uvx).rgb * bw.x + texture(leaf_tex, uvy).rgb * bw.y
			+ texture(leaf_tex, uvz).rgb * bw.z;
		vec3 nx = texture(leaf_nrm, uvx).xyz * 2.0 - 1.0;
		vec3 ny = texture(leaf_nrm, uvy).xyz * 2.0 - 1.0;
		vec3 nz = texture(leaf_nrm, uvz).xyz * 2.0 - 1.0;
		vec3 off = (vec3(0.0, nx.y, nx.x) * bw.x + vec3(ny.x, 0.0, ny.y) * bw.y
			+ vec3(nz.x, nz.y, 0.0) * bw.z) * leaf_bump;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(wnrm + off), 0.0)).xyz);
	}
	ALBEDO = c;
	ROUGHNESS = veg_roughness;
	METALLIC = 0.0;
	SPECULAR = use_leaf ? 0.24 : 0.18;
	// NO `ALPHA =` LINE, DELIBERATELY. Godot's shader compiler decides a
	// spatial shader is TRANSPARENT the moment the source assigns ALPHA at
	// all — it does not check whether the value is 1.0. The first cut wrote
	// `ALPHA = tint.a * COLOR.a` for tidiness and every live-oak canopy in the
	// game turned into smoked glass: the freeway, the billboards and the
	// downtown skyline were legible THROUGH the crowns at `mott_flora`. Every
	// layer this material serves is opaque; leaving ALPHA unwritten is what
	// keeps it that way.
}
"""


## Registered once, lazily, BEFORE any wind Shader is compiled — a shader that
## references a global which does not exist yet logs an ERROR at compile time
## and fails the zero-error gate. Same guard discipline as `_register_wetness`:
## a bool, never `global_shader_parameter_get_list()`, which is editor-only and
## logs an error at runtime. Adding a name that already exists ALSO logs an
## error, hence the flag rather than a blind add.
static var _wind_registered := false


## Night ramp for the interior-mapped glass. Registered BEFORE the glass shader
## compiles, same rule as `road_wetness` and `wind_gust`: a shader that names a
## global which does not exist yet fails to compile and logs an error line.
static var _night_registered := false


static func _register_night() -> void:
	if _night_registered:
		return
	_night_registered = true
	RenderingServer.global_shader_parameter_add("night_level",
		RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


## 0 = noon, 1 = full night. Driven by `facade_kit`'s own one-node driver off
## `streetlight_glow.level_for_hour`, so the shop windows come on at the same
## minute the streetlights, the suburb and downtown do.
static func set_night_level(l: float) -> void:
	if not _night_registered:
		return
	RenderingServer.global_shader_parameter_set("night_level", clampf(l, 0.0, 1.0))


static func _register_wind() -> void:
	if _wind_registered:
		return
	_wind_registered = true
	RenderingServer.global_shader_parameter_add("wind_gust",
		RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


## Weather hook, mirroring `set_wetness`. 0.0 = still air (the default, and the
## state every archived screenshot was taken in), 1.0 = a hard gust. Safe to
## call before any vegetation exists.
static func set_wind_gust(g: float) -> void:
	if not _wind_registered:
		return
	RenderingServer.global_shader_parameter_set("wind_gust", clampf(g, 0.0, 2.0))


## Vegetation material. `two_sided` picks a second compiled program rather than
## a uniform, because cull mode is a `render_mode`, not a parameter — and the
## card flora (grass, bluestem, yucca, pear pads, tumbleweeds) are all
## CULL_DISABLED while the canopies are not. Two programs, both shared by every
## layer that asks: the whole prairie is still one pipeline state.
##
## SHADOW POLICY (D-028) IS NOT AFFECTED BY THIS FUNCTION. Wind is a material
## swap; `cast_shadow` lives on the MultiMeshInstance3D and every caller below
## leaves the flag exactly as its layer set it. Two-sided cards stay OFF.
static func wind_material(rough: float, two_sided: bool, sway: float,
		sway_gust: float, rate: float, flutter := 0.0,
		rigid_mix := 0.0, leaf := false, leaf_seed := 3) -> ShaderMaterial:
	_register_wind()
	var key := "wind2s" if two_sided else "wind"
	var src := WIND_SHADER
	if two_sided:
		src = src.replace("render_mode diffuse_burley, specular_schlick_ggx;",
			"render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;")
	var m := ShaderMaterial.new()
	m.shader = _shader(key, src)
	m.set_shader_parameter("veg_roughness", rough)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_gust", sway_gust)
	m.set_shader_parameter("rate", rate)
	m.set_shader_parameter("flutter", flutter)
	m.set_shader_parameter("rigid_mix", rigid_mix)
	if leaf and not OS.get_cmdline_user_args().has("--leaf-legacy"):   # A/B: flat crowns from the same tree
		var ft: Array = TEX.foliage_textures(leaf_seed)
		m.set_shader_parameter("use_leaf", true)
		m.set_shader_parameter("leaf_tex", ft[0])
		m.set_shader_parameter("leaf_nrm", ft[1])
	return m


## Swap a built layer's material_override for a wind one, by node name. This is
## how the three dressing files get wind WITHOUT touching a single seeded draw,
## a single transform, or a single `casts` flag: the MultiMesh is already built
## and populated, and only the material it renders with changes. Returns true
## if the node was found, so a caller can be told when it renamed a layer.
static func apply_wind(parent: Node, layer: String, rough: float,
		two_sided: bool, sway: float, sway_gust: float, rate: float,
		flutter := 0.0, rigid_mix := 0.0, leaf := false, leaf_seed := 3) -> bool:
	if legacy() or TEX.v1():
		return false
	var n := parent.get_node_or_null(NodePath(layer))
	if n == null or not (n is MultiMeshInstance3D):
		return false
	(n as MultiMeshInstance3D).material_override = wind_material(
		rough, two_sided, sway, sway_gust, rate, flutter, rigid_mix, leaf, leaf_seed)
	return true
