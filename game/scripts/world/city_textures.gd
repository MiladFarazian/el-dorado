extends RefCounted
## PROCEDURAL TEXTURE KIT — every texture in the game is built here, in code,
## at boot (no asset files, per the agent-legibility doctrine). All materials
## use WORLD-space triplanar mapping so one shared material paints boxes of any
## size with correctly-scaled detail: windows stay window-sized on every tower,
## bricks stay brick-sized on every wall, regardless of mesh or MultiMesh scale.
## Deterministic: fixed seeds, no Time/Date. Small images (64-192 px) built
## once with set_pixel loops — a few ms at boot, never touched again.

const WINDOW_SEED := 7001
const BRICK_SEED := 7002
const NOISE_SEED := 7003


## Tower glass: a 4x4 grid of window cells — dark blue-green panes in near-black
## mullions, ~28% of panes warm-lit on the emission map so downtown glows at
## night for free (sky_weather dims the sun; emission stays). World tile:
## 9.6 m wide x 12.8 m tall = 2.4 m windows on 3.2 m floors.
# ---- D-104 DAYLIGHT SUPPRESSION ----------------------------------------------
# Every lit-window material this kit hands out registers here with its NIGHT
# energy; `set_night_level()` (driven by facade_kit's StoreNightDriver from
# streetlight_glow.level_for_hour, the same clock every other district uses)
# lerps them from 0 at noon to full at night. Before this the greybox towers and
# the hospital burned their windows at 1.4 all day (`sky_wide`, both arms).
static var _night_mats: Array = []          # [[material, night_energy], ...]


static func _register_night(m: StandardMaterial3D, night_energy: float) -> void:
	_night_mats.append([m, night_energy])


static func set_night_level(level: float) -> void:
	var k := clampf(level, 0.0, 1.0)
	for e in _night_mats:
		var m: StandardMaterial3D = e[0]
		if is_instance_valid(m):
			m.emission_energy_multiplier = float(e[1]) * k


static func tower_material(tint: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = WINDOW_SEED
	var size := 128
	var cell := 32
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var emit := Image.create(size, size, false, Image.FORMAT_RGB8)
	var mullion := Color(0.09, 0.10, 0.11)
	var lit := Color(1.0, 0.83, 0.55)
	# M23 RELIEF + ROUGHNESS. A curtain wall is not one surface, it is two: a
	# 60 mm aluminium mullion cap standing proud, and glass set behind it. That
	# 60 mm step is the entire reason a real tower has a grid of hard shadow
	# lines down its face in the morning and this one did not. Roughness is the
	# other half and it is the bigger SSR lever: glass at 0.10 returns the
	# skyline, anodised aluminium at 0.55 returns a broad sheen, and the two
	# together are what stops a tower reading as one printed sheet.
	var hgt := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	hgt.resize(size * size)
	rgh.resize(size * size)
	for cy in 4:
		for cx in 4:
			var is_lit := rng.randf() < 0.28
			var shade := rng.randf_range(0.5, 0.95)  # per-pane glass depth
			for py in cell:
				for px in cell:
					var x := cx * cell + px
					var y := cy * cell + py
					var frame := px < 3 or px >= cell - 3 or py < 4 or py >= cell - 2
					# Glass sits 60 mm behind the mullion face; the sill rail is
					# a little deeper again so each floor gets a shadow line.
					hgt[y * size + x] = 0.0 if frame else -0.060
					if not frame and py >= cell - 4:
						hgt[y * size + x] = -0.075
					rgh[y * size + x] = 0.55 if frame else 0.10
					if frame:
						albedo.set_pixel(x, y, mullion)
						emit.set_pixel(x, y, Color.BLACK)
					else:
						# Dark glass: panes sit well below mid-gray so daylight
						# reads as tinted curtain wall, not white glare.
						var v := shade * (0.85 + 0.15 * float(py) / float(cell)) * 0.55
						albedo.set_pixel(x, y, Color(tint.r * v, tint.g * v, tint.b * v))
						emit.set_pixel(x, y, lit * rng.randf_range(0.85, 1.0) if is_lit else Color.BLACK)
	var m := _triplanar(albedo, Vector3(1.0 / 9.6, 1.0 / 12.8, 1.0 / 9.6))
	# THE GLASS DECISION, tower half (M23). This material is OPAQUE and it stays
	# opaque: Godot 4's SSR samples the OPAQUE pass only, so a transparent tower
	# pane is the one surface in the city that can never reflect the city. At
	# 40 m nobody is looking THROUGH a curtain wall anyway — they are looking at
	# what it reflects. So: metallic 0.1 -> 0.0 (metallic on glass throws away
	# the fresnel ramp, D-030), specular up, and the roughness map carries the
	# 0.10 glass / 0.55 mullion split that makes the reflection break at every
	# mullion instead of running as one unbroken mirror sheet.
	m.roughness = 1.0          # ceiling: the map below carries the real value
	m.metallic = 0.0
	m.metallic_specular = 0.85
	m.emission_enabled = true
	emit.generate_mipmaps()
	m.emission_texture = ImageTexture.create_from_image(emit)
	# emission_operator is ADD: the flat emission color is SUMMED with the
	# texture. White here made every facade emit 0.75 white day and night
	# (bisection-caught). Black = texture only.
	m.emission = Color(0, 0, 0)
	m.emission_energy_multiplier = 0.0   # D-104: lit windows follow the night level; 1.4 burned at noon
	_register_night(m, 1.4)
	m.vertex_color_use_as_albedo = true  # MultiMesh per-instance facade tinting
	# gain = 1 / 75 mm texel (9.6 m tile / 128 px). normal_scale 0.8 because a
	# 60 mm step across one texel is a ~39 deg wall and at full strength the
	# grid photographed as corrugation from `trust_tower`.
	return attach_relief(m, relief_normal(hgt, size, 13.33), 0.8,
		relief_rough(rgh, size), 1.0) as StandardMaterial3D


## Running-bond brick: 8 courses with alternating offset, light mortar lines,
## per-brick tint jitter. World tile 2.56 m x 1.28 m -> 0.64 m x 0.16 m bricks.
static func brick_material(base: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = BRICK_SEED
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var mortar := Color(0.62, 0.58, 0.52)
	var course := 16  # px per brick row
	var brick_w := 32
	# M23 RELIEF. Heights are in METRES so the number in the code is the number
	# a bricklayer would say: the mortar joint is struck 10 mm behind the brick
	# face. At 2.56 m / 128 px the tile is 20 mm per texel, so that recess is
	# half a texel of depth across one texel of run — a genuinely steep joint
	# wall, which is exactly what makes brick read as brick under a low sun
	# instead of as printed wallpaper.
	var hgt := PackedFloat32Array()
	hgt.resize(size * size)
	for y in size:
		var row := y / course
		var offset := (brick_w / 2) if row % 2 == 1 else 0
		for x in size:
			var in_mortar_row := y % course >= course - 2
			var in_mortar_col := (x + offset) % brick_w >= brick_w - 2
			if in_mortar_row or in_mortar_col:
				img.set_pixel(x, y, mortar)
				hgt[y * size + x] = -0.010
			else:
				var bid := (x + offset) / brick_w + row * 7
				var seeded := RandomNumberGenerator.new()
				seeded.seed = BRICK_SEED + bid
				var v := seeded.randf_range(0.82, 1.12)
				img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v))
				# Bricks are not coplanar and they are not flat. A +/-1.5 mm
				# per-brick set-out plus a 1 mm crown across the face is what
				# stops a wall of them returning one single specular sheet.
				var fx := float(posmod(x + offset, brick_w)) / float(brick_w) - 0.5
				var fy := float(y % course) / float(course) - 0.5
				hgt[y * size + x] = (v - 0.97) * 0.010 \
					- (fx * fx + fy * fy) * 0.004
	var m := _triplanar(img, Vector3(1.0 / 2.56, 1.0 / 1.28, 1.0 / 2.56))
	m.roughness = 0.92
	# gain = 1 / texel size in metres (2.56 m / 128 px = 20 mm), so the encoded
	# slope is a real world gradient and `normal_scale` stays a taste knob.
	return attach_relief(m, relief_normal(hgt, size, 50.0), 1.0) as StandardMaterial3D


## Fine-grained asphalt: dark noise + sparse pale aggregate speckle. 7 m tiles.
static func asphalt_material() -> StandardMaterial3D:
	var img := _noise_image(128, 0.10, Color(0.15, 0.15, 0.16), Color(0.20, 0.20, 0.21))
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	for i in 260:  # aggregate flecks
		img.set_pixel(rng.randi_range(0, 127), rng.randi_range(0, 127),
			Color(0.30, 0.30, 0.31))
	var m := _triplanar(img, Vector3.ONE / 7.0)
	m.roughness = 0.95
	return m


## Broom-finished concrete with expansion joints every world tile (4.5 m).
static func concrete_material() -> StandardMaterial3D:
	var img := _noise_image(128, 0.14, Color(0.44, 0.43, 0.40), Color(0.51, 0.50, 0.47))
	var joint := Color(0.38, 0.37, 0.34)
	for i in 128:  # joint cross along the tile edges
		img.set_pixel(i, 0, joint)
		img.set_pixel(i, 1, joint)
		img.set_pixel(0, i, joint)
		img.set_pixel(1, i, joint)
	var m := _triplanar(img, Vector3.ONE / 4.5)
	m.roughness = 0.9
	return m


## North Texas prairie in late July: mostly scorched tan, patches holding on to
## a tired olive green. (First cut was golf-course mint — review said no.)
static func prairie_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED + 7
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var dry := Color(0.55, 0.47, 0.31)
	var green := Color(0.42, 0.43, 0.26)
	for y in 128:
		for x in 128:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, dry.lerp(green, clampf(n * 1.1 - 0.25, 0.0, 1.0)))
	var m := _triplanar(img, Vector3.ONE / 19.0)
	m.roughness = 1.0
	return m


## Shared plumbing: image -> world-triplanar StandardMaterial3D.
static func _triplanar(img: Image, scale: Vector3) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


static func _noise_image(size: int, freq: float, a: Color, b: Color) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.frequency = freq * 128.0 / float(size)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, a.lerp(b, n))
	return img


## Storefront glazing (M14): dark retail glass for the podium bays. Not
## near-black — the D-013 lesson: too-dark glass reads as a hole at street
## range — so it keeps a blue-grey level plus reflectivity. lit=true adds a
## constant warm interior glow, peaking at 0.84: safely UNDER the 1.05 HDR
## bloom threshold, so night storefronts read warm, never haze.
static func storefront_glass_material(lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.15, 0.17)
	m.roughness = 0.14
	m.metallic = 0.22
	m.metallic_specular = 0.55
	if lit:
		m.emission_enabled = true
		m.emission = Color(0.84, 0.64, 0.36)
		m.emission_energy_multiplier = 0.0   # D-104: night-ramped below
		_register_night(m, 1.0)
	return m


## Soft radial falloff sprite (M14): the streetlight pool disc. White with a
## smoothstep alpha fade to zero at the rim — tint and level come from the
## pool material's albedo_color, so one texture serves every state.
static func light_pool_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(float(x) - 31.5, float(y) - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)  # smoothstep: no hard rim ring
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ======================= M16 SCENIC KIT (append-only) ========================
## Everything below is additive: new functions only, no existing texture or
## material changed. Seeds are literal and local — nothing here draws from any
## gameplay or layout RNG stream.

const CLOUD_SEED := 7101
const PATCH_SEED := 7102


## Seamless three-band value noise for the sky shader's cumulus deck. Each
## channel is a tileable fBm at a different frequency band (R broad masses,
## G billows, B edge detail); the shader sums them at 1x / 2x / 5x — INTEGER
## multipliers, so the drift offset can wrap at 1.0 without popping.
## Tileability is structural: every octave's lattice wraps at its own period,
## which divides the image size, so the image repeats with no seam.
static func cloud_noise_texture() -> ImageTexture:
	var size := 128
	var periods: Array = [[4, 8], [8, 16], [16, 32]]
	var amps: Array = [[0.62, 0.38], [0.60, 0.40], [0.58, 0.42]]
	var grids: Array = []
	for band in 3:
		var g: Array = []
		for oct in 2:
			g.append(_lattice(int(periods[band][oct]), CLOUD_SEED + band * 31 + oct * 7))
		grids.append(g)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := [0.0, 0.0, 0.0]
			for band in 3:
				for oct in 2:
					var p: int = periods[band][oct]
					var s := float(p) / float(size)
					v[band] += float(amps[band][oct]) * _vnoise(
						grids[band][oct], p, float(x) * s, float(y) * s)
			img.set_pixel(x, y, Color(clampf(v[0], 0.0, 1.0),
				clampf(v[1], 0.0, 1.0), clampf(v[2], 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Ground-patch decal for prairie colour breakup: a soft blotch whose rim is
## eaten by noise, so a field of them reads as soil and burn variation rather
## than a grid of circles. RGB carries interior mottling, A carries the shape;
## the patch's actual colour is the MultiMesh instance colour.
static func prairie_patch_texture() -> ImageTexture:
	var size := 96
	var g0 := _lattice(6, PATCH_SEED)
	var g1 := _lattice(12, PATCH_SEED + 3)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (float(x) + 0.5) / float(size) - 0.5
			var w := (float(y) + 0.5) / float(size) - 0.5
			var r := sqrt(u * u + w * w) * 2.0
			var n := _vnoise(g0, 6, float(x) * 6.0 / size, float(y) * 6.0 / size) * 0.62 \
				+ _vnoise(g1, 12, float(x) * 12.0 / size, float(y) * 12.0 / size) * 0.38
			var a := clampf(1.0 - r * (0.70 + 0.62 * n), 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := 0.78 + 0.34 * n
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Wet concrete for the floodway's low-flow trickle. Dark, smooth and specular
## so it catches the sky the way standing water on a channel floor does; the
## instance colour carries both the tint and how damp each strip reads.
static func wet_concrete_material(gloss: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.06 if gloss else 0.30
	m.metallic = 0.25 if gloss else 0.05
	m.metallic_specular = 0.90 if gloss else 0.55
	return m


## Tileable value-noise lattice: `period` x `period` random values in [0,1).
static func _lattice(period: int, s: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var g := PackedFloat32Array()
	g.resize(period * period)
	for i in period * period:
		g[i] = rng.randf()
	return g


## Bilinear value noise over a wrapping lattice; (u,v) are in lattice units.
static func _vnoise(g: PackedFloat32Array, period: int, u: float, v: float) -> float:
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - float(x0)
	var fy := v - float(y0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x1 := posmod(x0 + 1, period)
	var y1 := posmod(y0 + 1, period)
	x0 = posmod(x0, period)
	y0 = posmod(y0, period)
	return lerpf(lerpf(g[y0 * period + x0], g[y0 * period + x1], fx),
		lerpf(g[y1 * period + x0], g[y1 * period + x1], fx), fy)


# =============== M21 DOWNTOWN VOCABULARY (append-only, defect D-023) =========
## Downtown shipped ONE facade — `tower_material` on every shaft — so 108
## towers read as one building repeated. These five materials are the other
## halves of the architectural vocabulary: each is a different WINDOW LOGIC
## (vertical pier / horizontal ribbon / punched hole / curtain grid / none),
## so two buildings side by side differ at street level as well as in outline.
## All world-triplanar on the same 9.6 m x 12.8 m tile as the original glass
## (2.4 m bays on 3.2 m floors), so they drop onto any box at any scale.
## Emission map law: flat emission stays BLACK, the texture carries the lit
## panes (`emission_operator` is ADD — a white flat colour makes the whole
## facade glow day and night, bisection-caught in M8).

const FACADE_SEED := 7201


## ART DECO / pre-war setback tower: limestone piers running the full height
## with the window recessed BETWEEN them in shadow, and a darker spandrel under
## each sill. Reads vertical at every distance — the opposite of `slab_ribbon`.
static func deco_stone_material(tint: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = FACADE_SEED
	var albedo := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var emit := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var lit := Color(1.0, 0.86, 0.58)
	# M23 RELIEF. A deco tower's entire read is DEPTH between the piers: the
	# glass sits 300 mm back inside a stone reveal. The albedo already faked
	# that with three value steps (0.55 reveal, 0.26 slot, 1.06 sunlit return),
	# which is a painting of a shadow that never moves. With a real normal the
	# reveal darkens on the shaded side of the building and lights on the sunny
	# one, which is the whole difference between a facade and a photograph of
	# one. Limestone is rough (0.86); only the slot is glass (0.14).
	var hgt := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	hgt.resize(128 * 128)
	rgh.resize(128 * 128)
	for cy in 4:
		for cx in 4:
			var is_lit := rng.randf() < 0.26
			var pane := rng.randf_range(0.55, 0.95)
			for py in 32:
				for px in 32:
					var x := cx * 32 + px
					var y := cy * 32 + py
					var c := tint
					var e := Color.BLACK
					var hh := 0.0
					var rr := 0.86
					if py >= 26:                       # spandrel panel under the sill
						c = tint * 0.80
						hh = -0.055
						if py >= 30:
							c = tint * 0.62           # shadow line at the floor slab
							hh = -0.095
					elif px >= 11 and px < 21 and py >= 3:
						c = tint * 0.26 * pane         # the recessed window slot
						hh = -0.300
						rr = 0.14
						if is_lit:
							e = lit * rng.randf_range(0.8, 1.0)
					elif px >= 9 and px < 11:
						c = tint * 0.55                # reveal shadow, pier's inner face
						hh = -0.150
					elif px >= 21 and px < 23:
						c = tint * 1.06                # sunlit return of the next pier
						hh = -0.150
					elif px < 3 or px >= 29:
						c = tint * 0.88                # pier joint
						hh = -0.020
						rr = 0.94
					albedo.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
					emit.set_pixel(x, y, e)
					hgt[y * 128 + x] = hh
					rgh[y * 128 + x] = rr
	return _facade(albedo, emit, 0.78, 0.0, 1.1, hgt, rgh, 0.75)


## MID-CENTURY SLAB: a continuous horizontal glazing ribbon over a pale precast
## spandrel band, repeated every floor. No vertical accent anywhere — this is
## the type that makes the deco tower next door look vertical.
static func slab_ribbon_material(tint: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = FACADE_SEED + 11
	var albedo := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var emit := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var glass := Color(0.30, 0.42, 0.44)
	var lit := Color(0.98, 0.94, 0.80)
	# M23 RELIEF. The mid-century signature is a 200 mm shadow line where the
	# precast spandrel oversails the glazing ribbon — that line, running dead
	# level for the whole width of the building, is what makes this type read
	# horizontal from 300 m. It was painted (tint * 0.60) and therefore lit
	# from nowhere; now it is geometry the sun finds.
	var hgt := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	hgt.resize(128 * 128)
	rgh.resize(128 * 128)
	for cy in 4:
		for py in 32:
			for x in 128:
				var y := cy * 32 + py
				var c := tint
				var e := Color.BLACK
				var hh := 0.0
				var rr := 0.72                          # precast spandrel
				if py < 14:                             # the ribbon
					c = glass * (0.72 + 0.30 * float(py) / 14.0)
					hh = -0.200
					rr = 0.09                           # glazing: SSR lives here
					if x % 8 < 1:
						c = tint * 0.86                 # slim aluminium mullion
						hh = -0.140
						rr = 0.42
					elif py < 2 or py >= 12:
						c = glass * 0.55                # head and sill reveal
						hh = -0.245
						rr = 0.55
				else:
					c = tint * (0.98 if py < 30 else 0.72)
					hh = 0.0 if py < 30 else -0.035
					if py == 14 or py == 15:
						c = tint * 0.60                 # drip edge under the glass
						hh = -0.060
						rr = 0.86
				albedo.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
				emit.set_pixel(x, y, e)
				hgt[y * 128 + x] = hh
				rgh[y * 128 + x] = rr
	# Light the ribbon in 16 px runs so a lit floor reads as a strip of office,
	# not as isolated panes — the mid-century signature after dark.
	for cy2 in 4:
		for run in 8:
			if rng.randf() >= 0.34:
				continue
			var glow := lit * rng.randf_range(0.72, 1.0)
			for py2 in range(2, 12):
				for px2 in range(run * 16 + 1, run * 16 + 16):
					emit.set_pixel(px2, cy2 * 32 + py2, glow)
	return _facade(albedo, emit, 0.52, 0.0, 1.25, hgt, rgh, 0.8)


## PRE-WAR MASONRY: running-bond brick with punched window openings, a pale
## stone sill under each and a flat-arch lintel over it. The only type whose
## wall is mostly SOLID — from 300 m it reads as a warm mass, not a grid.
static func masonry_window_material(base: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = FACADE_SEED + 23
	var albedo := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var emit := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var mortar := Color(0.60, 0.56, 0.50)
	var stone := Color(0.72, 0.69, 0.62)
	var lit := Color(1.0, 0.80, 0.48)
	# Per-brick value jitter from a small precomputed table (the M8 brick builder
	# allocates one RNG per pixel; 16 k allocations is a boot cost worth skipping).
	var jitter := PackedFloat32Array()
	jitter.resize(256)
	for i in 256:
		jitter[i] = rng.randf_range(0.80, 1.14)
	# M23 RELIEF. This is the type the mandate names: a PUNCHED opening in a
	# solid wall. The window is 200 mm behind the brick face and the stone sill
	# stands 40 mm PROUD of it — a positive and a negative in the same cell,
	# which is what a normal map can express and a value step cannot. Mortar is
	# raked 10 mm exactly as in `brick_material`, so the two brick surfaces in
	# the game agree about what a joint is.
	var hgt := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	hgt.resize(128 * 128)
	rgh.resize(128 * 128)
	for cy in 4:
		for cx in 4:
			var is_lit := rng.randf() < 0.24
			var shade := rng.randf_range(0.45, 0.8)
			for py in 32:
				for px in 32:
					var x := cx * 32 + px
					var y := cy * 32 + py
					var c: Color
					var hh := 0.0
					var rr := 0.88
					if px >= 9 and px < 23 and py >= 6 and py < 24:
						c = Color(0.10, 0.11, 0.13) * (shade + 0.6)   # the opening
						hh = -0.200
						rr = 0.16
						emit.set_pixel(x, y, lit * rng.randf_range(0.85, 1.0) \
							if is_lit else Color.BLACK)
					elif px >= 7 and px < 25 and py >= 24 and py < 26:
						c = stone                                     # sill
						hh = 0.040
						rr = 0.80
						emit.set_pixel(x, y, Color.BLACK)
					elif px >= 8 and px < 24 and py >= 4 and py < 6:
						c = stone * 0.88                              # lintel
						hh = 0.020
						rr = 0.80
						emit.set_pixel(x, y, Color.BLACK)
					else:
						var row := y / 3
						var off := 4 if row % 2 == 1 else 0
						if y % 3 == 2 or (x + off) % 8 == 7:
							c = mortar
							hh = -0.010
							rr = 0.96
						else:
							c = base * jitter[posmod((x + off) / 8 + row * 13, 256)]
							hh = (jitter[posmod((x + off) / 8 + row * 13, 256)] - 0.97) * 0.008
						emit.set_pixel(x, y, Color.BLACK)
					albedo.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
					hgt[y * 128 + x] = hh
					rgh[y * 128 + x] = rr
	return _facade(albedo, emit, 0.94, 0.0, 1.05, hgt, rgh, 0.9)


## BLACK-GLASS CORPORATE CURTAIN WALL: dark glazing in a bright aluminium grid,
## the panes graded top-dark to bottom-light so the wall reads as reflection.
## Kept off pure black — the D-013 lesson: too-dark glass reads as a hole.
static func dark_curtain_material(tint: Color) -> StandardMaterial3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = FACADE_SEED + 37
	var albedo := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var emit := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var frame := Color(0.52, 0.54, 0.57)
	var lit := Color(0.80, 0.88, 1.0)
	# M23 — THE BIGGEST SSR SURFACE IN THE GAME. 22 of the 108 downtown towers
	# are this material and it is the wall the skyline is reflected in. Three
	# changes, all of them the same argument:
	#  * metallic 0.42 -> 0.0. `metallic` means "no diffuse, the colour IS the
	#    reflection" and it discards the fresnel ramp that is the entire visual
	#    signature of glass (D-030 said this about storefronts and then left the
	#    corporate curtain wall on 0.42, which is the worst offender).
	#  * roughness map: pane 0.055, aluminium frame 0.34. At a single 0.24 the
	#    whole wall returned one smeared reflection with no grid in it.
	#  * a 45 mm mullion step so the grid casts, and so SSR breaks at every
	#    frame member instead of running as one sheet from parapet to plaza.
	var hgt := PackedFloat32Array()
	var rgh := PackedFloat32Array()
	hgt.resize(128 * 128)
	rgh.resize(128 * 128)
	for cy in 4:
		for cx in 4:
			var is_lit := rng.randf() < 0.17
			var pane := rng.randf_range(0.7, 1.05)
			for py in 32:
				for px in 32:
					var x := cx * 32 + px
					var y := cy * 32 + py
					var c: Color
					var e := Color.BLACK
					if px < 2 or px >= 30 or py < 2 or py >= 30:
						c = frame
						hgt[y * 128 + x] = 0.0
						rgh[y * 128 + x] = 0.34
					else:
						var g := pane * (0.62 + 0.55 * float(py) / 32.0)
						c = tint * g
						hgt[y * 128 + x] = -0.045
						rgh[y * 128 + x] = 0.055
						if is_lit:
							e = lit * rng.randf_range(0.7, 0.95)
					albedo.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
					emit.set_pixel(x, y, e)
	var m := _facade(albedo, emit, 0.24, 0.0, 0.95, hgt, rgh, 0.7)
	m.metallic_specular = 0.95
	return m


## BOARD-FORMED CONCRETE: horizontal form-tie lines every 0.6 m. The parking
## decks, the construction frames, and every cornice/parapet in the pass.
static func board_concrete_material() -> StandardMaterial3D:
	var img := _noise_image(128, 0.16, Color(0.55, 0.54, 0.51), Color(0.63, 0.62, 0.58))
	for y in 128:
		if y % 8 == 0:
			for x in 128:
				img.set_pixel(x, y, Color(0.44, 0.43, 0.40))
		elif y % 8 == 1:
			for x2 in 128:
				img.set_pixel(x2, y, Color(0.66, 0.65, 0.61))
	var m := _triplanar(img, Vector3.ONE / 4.8)
	m.roughness = 0.93
	m.vertex_color_use_as_albedo = true
	# M23 RELIEF. Board-formed concrete is DEFINED by its relief — the whole
	# point of the finish is that the timber grain and the 12 mm form-tie
	# groove are visible in raking light. Height is read back out of the albedo
	# because for this surface the noise IS the height: the pale texels are the
	# proud board faces and the dark ones are between them.
	var hgt := PackedFloat32Array()
	hgt.resize(128 * 128)
	for y in 128:
		for x in 128:
			var v := (img.get_pixel(x, y).r - 0.44) / 0.22
			var h := clampf(v, 0.0, 1.0) * 0.004
			if y % 8 == 0:
				h = -0.012                     # the form-tie groove
			elif y % 8 == 1:
				h = 0.004                      # the board lip above it
			hgt[y * 128 + x] = h
	# gain = 1 / 37.5 mm texel (4.8 m tile / 128 px).
	return attach_relief(m, relief_normal(hgt, 128, 26.67), 1.0) as StandardMaterial3D


## PAINTED CONCRETE BLOCK: the low commercial box under a rooftop billboard.
## Faint 0.4 m x 0.2 m coursing, otherwise a flat painted field.
static func painted_block_material() -> StandardMaterial3D:
	var img := _noise_image(128, 0.22, Color(0.86, 0.85, 0.82), Color(0.94, 0.93, 0.90))
	for y in 128:
		var row := y / 8
		var off := 8 if row % 2 == 1 else 0
		for x in 128:
			if y % 8 == 7 or (x + off) % 16 == 15:
				img.set_pixel(x, y, Color(0.74, 0.73, 0.70))
	var m := _triplanar(img, Vector3.ONE / 6.4)
	m.roughness = 0.90
	m.vertex_color_use_as_albedo = true
	# M23: 6 mm raked joint on a 0.4 x 0.2 m block coursing. Small, but it is
	# the difference between a painted CMU wall and a flat painted plane, and
	# these boxes sit under the rooftop billboards where the sun rakes them.
	var hgt := PackedFloat32Array()
	hgt.resize(128 * 128)
	for y in 128:
		var row := y / 8
		var off := 8 if row % 2 == 1 else 0
		for x in 128:
			hgt[y * 128 + x] = -0.006 if (y % 8 == 7 or (x + off) % 16 == 15) \
				else (img.get_pixel(x, y).r - 0.86) / 0.08 * 0.001
	# gain = 1 / 50 mm texel (6.4 m tile / 128 px).
	return attach_relief(m, relief_normal(hgt, 128, 20.0), 1.0) as StandardMaterial3D


## Shared plumbing for the five facade materials: albedo + lit-pane emission,
## world-triplanar on the 9.6 x 12.8 m bay tile, MultiMesh instance tinting on.
## M23: `hgt` and `rgh` are optional parallel fields in the SAME 128 px lattice
## the albedo was painted in. Heights are metres; the gain converts them to a
## world gradient (the bay tile is 9.6 m over 128 px = 75 mm per texel, so
## 1/0.075 = 13.33). Passing neither leaves the material exactly as it shipped.
static func _facade(albedo: Image, emit: Image, rough: float, metal: float,
		energy: float, hgt := PackedFloat32Array(), rgh := PackedFloat32Array(),
		nscale := 1.0) -> StandardMaterial3D:
	var m := _triplanar(albedo, Vector3(1.0 / 9.6, 1.0 / 12.8, 1.0 / 9.6))
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	emit.generate_mipmaps()
	m.emission_texture = ImageTexture.create_from_image(emit)
	m.emission = Color(0, 0, 0)          # texture only — see the M8 note above
	m.emission_energy_multiplier = 0.0   # D-104: `energy` is the NIGHT value; the ramp owns it
	_register_night(m, energy)
	m.vertex_color_use_as_albedo = true
	if not hgt.is_empty():
		attach_relief(m, relief_normal(hgt, 128, 13.33), nscale,
			relief_rough(rgh, 128) if not rgh.is_empty() else null,
			1.0 if not rgh.is_empty() else -1.0)
	return m


# ============ M22 SURFACE-SHADER TEXTURE KIT (append-only) ===================
## Data textures for `city_shaders.gd`. These are NOT pictures — every channel
## is a signal a shader reads, so nothing here is authored to look like anything
## on its own. Both are TILEABLE by construction (every octave runs on a
## wrapping lattice whose period divides the image size, the same guarantee
## `cloud_noise_texture` relies on), which matters far more here than it did for
## the sky: the road tile repeats every 7 m across 566,000 m² of pavement, so a
## seam would print a visible grid over the entire city.
##
## Note what this replaces. `asphalt_material()`'s image is FastNoiseLite, which
## does not wrap — the shipped asphalt has always had a seam every 7 m, hidden
## only by being nearly black. These do not.

const ROAD_SEED := 7301
const ROAD_SURF_SIZE := 128     # grain tile: 128 px over 7 m = 18 px/m
const ROAD_MACRO_SIZE := 128    # variation tile: 128 px over 64 m = 2 px/m

## Built once per kind and shared. `asphalt_material()` is called from THREE
## sites (greybox_city.gd:143, city_dressing.gd:2238, :2270), each of which used
## to rebuild an identical image and hand the renderer a third redundant
## texture; this cache means the shader path builds each surface exactly once.
static var _road_tex: Dictionary = {}


## R micro-albedo grain | G,B micro-normal XZ slope | A porosity.
## Porosity is the channel that makes rain look right: it decides how much any
## given patch of surface drinks before it starts pooling.
static func road_surface_texture(kind: String) -> ImageTexture:
	var key := "surf_" + kind
	if _road_tex.has(key):
		return _road_tex[key]
	var n := ROAD_SURF_SIZE
	var h := PackedFloat32Array()
	h.resize(n * n)
	var concrete := kind == "concrete"
	# --- height field ------------------------------------------------------
	# Octave choice is the whole ballgame, and the first cut got it wrong in an
	# instructive way. A period-8 lattice on a 7 m tile makes 0.9 m features; two
	# metres from the camera those are half a metre across and read as water
	# stains, not as pavement. The fine tile's ONLY job is near-field micro
	# detail — long-wavelength variation belongs to the macro texture — so the
	# energy goes in the HIGH octaves, which also means it mips cleanly to flat
	# grey with distance instead of boiling.
	var g0 := _lattice(16, ROAD_SEED)
	var g1 := _lattice(32, ROAD_SEED + 5)
	var g2 := _lattice(64, ROAD_SEED + 11)
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			# Weighted hard toward the top octave. Mipmapping AVERAGES normals, so
			# fine grain flattens out with distance while any surviving low octave
			# keeps its slope — which is why a merely "reduced" 0.44 m octave still
			# photographed as rolling ripples, like wet fabric, at grazing angles.
			var f := _vnoise(g0, 16, u * 16.0, v * 16.0) * 0.13 \
				+ _vnoise(g1, 32, u * 32.0, v * 32.0) * 0.29 \
				+ _vnoise(g2, 64, u * 64.0, v * 64.0) * 0.58
			if concrete:
				# Broom finish: parallel drag marks, wavering slightly so they
				# read as bristle tracks and not as a printed ruling.
				var wob := _vnoise(g0, 16, u * 16.0, v * 16.0) * 0.18
				f = f * 0.55 + 0.45 * (0.5 + 0.5 * sin((v + wob) * TAU * 26.0))
				# Expansion joint along two edges of the tile (4.5 m grid).
				var edge := minf(float(x), float(y))
				if edge < 2.0:
					f -= 0.55 * (1.0 - edge * 0.5)
			h[y * n + x] = f
	if not concrete:
		# Exposed aggregate, stamped as domes and wrapped at the tile edge so a
		# stone crossing the seam completes on the far side. Deliberately MANY and
		# SMALL: at 18 px/m a 3 px stone is 16 cm, and 16 cm stones with a strong
		# normal rim photographed as craters in the near field. Real asphalt
		# aggregate is 5-15 mm — under one texel — so what belongs here is dense
		# grain that survives as roughness breakup, not resolvable rocks.
		var rng := RandomNumberGenerator.new()
		rng.seed = ROAD_SEED + 3
		for i in 520:
			var sx := rng.randi_range(0, n - 1)
			var sy := rng.randi_range(0, n - 1)
			var rad := rng.randi_range(1, 2)
			var amp := rng.randf_range(0.06, 0.20)
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var d := sqrt(float(dx * dx + dy * dy)) / float(rad + 1)
					if d >= 1.0:
						continue
					var px := posmod(sx + dx, n)
					var py := posmod(sy + dy, n)
					h[py * n + px] += amp * (1.0 - d) * (1.0 - d)
	# --- normalise, then differentiate into slopes -------------------------
	var lo := 9e9
	var hi := -9e9
	for i in n * n:
		lo = minf(lo, h[i])
		hi = maxf(hi, h[i])
	var span := maxf(hi - lo, 0.0001)
	for i in n * n:
		h[i] = (h[i] - lo) / span
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# Slope gain: turns a height delta between neighbouring texels into the
	# [0,1] encoded perturbation the shader decodes. Tuned so ordinary grain
	# lands near the middle of the range and only stone rims approach the rails.
	var slope_gain := 3.0 if concrete else 3.4
	for y in n:
		for x in n:
			var xm := posmod(x - 1, n)
			var xp := posmod(x + 1, n)
			var ym := posmod(y - 1, n)
			var yp := posmod(y + 1, n)
			var dhdx := (h[y * n + xp] - h[y * n + xm]) * 0.5
			var dhdz := (h[yp * n + x] - h[ym * n + x]) * 0.5
			var hv := h[y * n + x]
			# Albedo: the high points are exposed aggregate (pale), the low
			# points are bitumen or a broom groove (dark). Stored around 0.5 so
			# the shader's `grain * 2.0` recovers a mean of 1.0.
			# Kept narrow on purpose. The shader recovers this as `grain * 2.0`,
			# so 0.5 is unity: this is a +/-16% swing, not a +/-38% one. Asphalt
			# is a VALUE, and a wide albedo swing at this frequency reads as dirt.
			var alb := 0.5 * (0.84 + 0.32 * hv) if not concrete \
				else 0.5 * (0.86 + 0.28 * hv)
			# Porosity: the low, open places drink. Grooves and the voids
			# between stones hold water; a polished stone crown does not.
			var por := clampf(1.0 - hv, 0.0, 1.0)
			img.set_pixel(x, y, Color(
				clampf(alb, 0.0, 1.0),
				clampf(0.5 - dhdx * slope_gain, 0.0, 1.0),
				clampf(0.5 - dhdz * slope_gain, 0.0, 1.0),
				por))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_road_tex[key] = t
	return t


## R repave slab | G drainage height | B oil/grime | A seams and cracks.
## Everything here is long-wavelength on purpose: its whole job is to break up
## the 7 m grain tile so the road stops reading as one repeating stamp out to
## the horizon. That repetition is a large part of why the surface looks
## "arcade" — real pavement is a patchwork of different ages of asphalt.
static func road_macro_texture(kind: String) -> ImageTexture:
	var key := "macro_" + kind
	if _road_tex.has(key):
		return _road_tex[key]
	var n := ROAD_MACRO_SIZE
	var concrete := kind == "concrete"
	var slab_l := _lattice(4, ROAD_SEED + 21)
	var drain_l := _lattice(3, ROAD_SEED + 29)
	var oil_l := _lattice(6, ROAD_SEED + 37)
	var oil2_l := _lattice(12, ROAD_SEED + 41)
	var crack_l := _lattice(8, ROAD_SEED + 53)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			# Repave slabs: quantised, so patches have EDGES. A smooth gradient
			# here reads as dirty lighting; a quantised one reads as a road that
			# has been cut open and filled in a dozen times.
			var s := _vnoise(slab_l, 4, u * 4.0, v * 4.0)
			var slab := floorf(s * 4.0) / 3.0
			# Drainage: the smooth long-wavelength height that decides where
			# water can sit at all.
			var drain := _vnoise(drain_l, 3, u * 3.0, v * 3.0)
			# Oil and rubber: two octaves so stains have cores and haloes.
			var oil := _vnoise(oil_l, 6, u * 6.0, v * 6.0) * 0.62 \
				+ _vnoise(oil2_l, 12, u * 12.0, v * 12.0) * 0.38
			oil = clampf((oil - 0.42) * 2.3, 0.0, 1.0)
			if concrete:
				oil *= 0.45
			# Seams: a ridged-noise network. |noise - 0.5| is near zero along
			# the zero-crossing contours of the field, which is a connected web
			# of thin lines — i.e. exactly how a road cracks.
			var c := _vnoise(crack_l, 8, u * 8.0, v * 8.0)
			var crack := 1.0 - smoothstep(0.0, 0.055, absf(c - 0.5))
			crack *= 0.85 if not concrete else 0.55
			img.set_pixel(x, y, Color(
				clampf(slab, 0.0, 1.0),
				clampf(drain, 0.0, 1.0),
				clampf(oil, 0.0, 1.0),
				clampf(crack, 0.0, 1.0)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_road_tex[key] = t
	return t


# ============ M23 SURFACE RELIEF KIT (append-only) ===========================
## WHY THIS EXISTS. Every generated texture in this file shipped as an ALBEDO
## AND NOTHING ELSE: no normal map, no roughness map, one scalar `roughness`
## per material. A census of the live tree at boot counted **425
## StandardMaterial3Ds, 0 of them normal-mapped and 0 roughness-mapped.** That
## is the definition of "reads as paper under raking sun", and it is the single
## thing standing between this city and SSR/SDFGI doing anything useful: a
## screen-space reflection off a perfectly flat, uniformly-rough wall is a
## mirror of the skyline with no break-up, and a flat roughness under GI is
## plastic.
##
## The fix is not new art. Every builder below already computes, pixel by
## pixel, a decision about what the surface IS at that texel — mortar or brick,
## pane or mullion, spandrel or glass, form-tie groove or slab face. That
## decision is a HEIGHT and a ROUGHNESS as much as it is a colour; the builders
## simply threw both away. So each one now fills a parallel `PackedFloat32Array`
## height field in the same loop it already runs, and two shared helpers turn
## that into a tangent-space normal map (central difference, wrapped) and a
## roughness map. The albedo images are byte-for-byte what they were.
##
## THE A/B ARMS. `--gfx-legacy` (D-030) still returns the pre-shader
## StandardMaterial3Ds. But the facade/brick/tower builders were NEVER part of
## that fork — they are the same object in both arms — so adding maps to them
## would have moved the control arm too, and there would be no way to reach
## this morning's build from this tree. `--gfx-v1` is the third arm: shaders on
## (D-030 as shipped), relief maps OFF. It is one `if` at the bottom of each
## builder, so the v1 arm is literally the old material, not a re-creation.
##
## NORMAL MAP CONVENTION: Godot expects X+, Y-, Z+ (green DOWN), which is the
## same sign convention the road shader's packed slope channels already use
## (`0.5 - dhdx * slope_gain`, city_textures.gd:road_surface_texture). Keeping
## one convention across the file is worth more than being "correct" in the
## abstract: a mixed convention shows up as one facade lit from the wrong side
## and nobody can ever see which.

const RELIEF_SEED := 7401

static var _v1 := -1


## Third A/B arm. `--gfx-v1` = the D-030 shaders WITHOUT the M23 relief maps —
## i.e. exactly what this tree rendered at the start of the day. Read once.
## `--gfx-legacy` counts too: that arm is the PRE-D-030 build, and a pre-D-030
## build with M23 normal maps bolted on is not a control, it is a third thing
## nobody asked for. One reader, both flags, so the two arms can never drift.
static func v1() -> bool:
	if _v1 < 0:
		var a := OS.get_cmdline_user_args()
		_v1 = 1 if (a.has("--gfx-v1") or a.has("--gfx-legacy")) else 0
	return _v1 == 1


## Height field -> tangent-space normal map. Central difference on a WRAPPED
## lattice, so the normal map tiles exactly as well as the albedo it came from
## (a seam in a normal map is far louder than a seam in an albedo — it is a
## visible crease of lighting, not a faint colour step).
##
## `gain` is in encoded units per unit height per texel: the whole tuning knob.
## The B channel is computed by normalising rather than pinned to 1.0, so a
## strong slope does not silently produce a non-unit normal that the engine
## renormalises into a weaker one than asked for.
# ---- FOLIAGE (M23) -----------------------------------------------------------
## A leaf-cluster tile for the crowns: [albedo, normal]. Three octaves of lattice
## noise sharpened into clusters; the albedo is a near-grey tint the instance
## colour multiplies (dark gaps, bright tops with a slight green lift), the
## normal is the cluster relief (12 mm over a ~1.4 m tile). Cached per seed.
static var _foliage_cache: Dictionary = {}


static func foliage_textures(seed: int) -> Array:
	if _foliage_cache.has(seed):
		return _foliage_cache[seed]
	var n := 128
	var g1 := _lattice(6, seed)
	var g2 := _lattice(14, seed + 71)
	var g3 := _lattice(29, seed + 907)
	var h := PackedFloat32Array()
	h.resize(n * n)
	var alb := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			var hh := clampf(_vnoise(g1, 6, u * 6.0, v * 6.0) * 0.55
				+ _vnoise(g2, 14, u * 14.0, v * 14.0) * 0.32
				+ _vnoise(g3, 29, u * 29.0, v * 29.0) * 0.13, 0.0, 1.0)
			var k := smoothstep(0.30, 0.72, hh)
			h[y * n + x] = k * 0.012
			var b := lerpf(0.58, 1.14, k)
			alb.set_pixel(x, y, Color(b * 0.94, b * 1.04, b * 0.86))
	alb.generate_mipmaps()
	var out := [ImageTexture.create_from_image(alb), relief_normal(h, n, 91.0)]
	_foliage_cache[seed] = out
	return out


# ========================= CHARACTER MICRO-DETAIL ============================
## M24. Two tiling normal maps for the shared character materials, generated
## once per process (256², ~0.5 s each, printed as a SKIN MICRO line). Both
## carry a MASK in alpha that the shader spends on albedo:
##   skin_micro  — a 6 cm tile: pores (0.6 mm cellular dimples), fine grain and
##                 a 1–2 cm undulation; alpha = mottle 0..1 for colour variation.
##   cloth_micro — an 8 cm tile: crumple folds at 2.7/1.1/0.5 cm and a 0.8 mm
##                 thread grain; alpha = fold shading (valleys dark).
## Heights are millimetres; `gain` turns mm-per-texel into slope.
static var _micro_cache: Dictionary = {}


static func skin_micro_texture() -> ImageTexture:
	if _micro_cache.has("skin"):
		return _micro_cache["skin"]
	var t0 := Time.get_ticks_msec()
	var n := 256
	var gp := _lattice(96, 4101)
	var gg := _lattice(128, 4177)
	var gu := _lattice(4, 4211)
	var gm1 := _lattice(5, 4243)
	var gm2 := _lattice(11, 4271)
	var h := PackedFloat32Array(); h.resize(n * n)
	var mask := PackedFloat32Array(); mask.resize(n * n)
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			var pore := smoothstep(0.60, 0.82, _vnoise(gp, 96, u * 96.0, v * 96.0))
			var grain := _vnoise(gg, 128, u * 128.0, v * 128.0) - 0.5
			var und := _vnoise(gu, 4, u * 4.0, v * 4.0) - 0.5
			var mot := clampf(_vnoise(gm1, 5, u * 5.0, v * 5.0) * 0.6
				+ _vnoise(gm2, 11, u * 11.0, v * 11.0) * 0.4, 0.0, 1.0)
			h[y * n + x] = -0.07 * pore + 0.015 * grain + 0.12 * und
			mask[y * n + x] = mot
	var tex := _relief_rgba(h, mask, n, 22.0)
	_micro_cache["skin"] = tex
	print("SKIN MICRO: skin 256^2 in %d ms" % (Time.get_ticks_msec() - t0))
	return tex


static func cloth_micro_texture() -> ImageTexture:
	if _micro_cache.has("cloth"):
		return _micro_cache["cloth"]
	var t0 := Time.get_ticks_msec()
	var n := 256
	var g1 := _lattice(3, 5101)
	var g2 := _lattice(7, 5153)
	var g3 := _lattice(15, 5197)
	var g4 := _lattice(64, 5231)
	var h := PackedFloat32Array(); h.resize(n * n)
	var mask := PackedFloat32Array(); mask.resize(n * n)
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			var cr := clampf(_vnoise(g1, 3, u * 3.0, v * 3.0) * 0.55
				+ _vnoise(g2, 7, u * 7.0, v * 7.0) * 0.30
				+ _vnoise(g3, 15, u * 15.0, v * 15.0) * 0.15, 0.0, 1.0)
			var thread := 0.5 * (sin(TAU * u * 96.0) + sin(TAU * v * 96.0))
			var slub := _vnoise(g4, 64, u * 64.0, v * 64.0) - 0.5
			h[y * n + x] = 0.9 * (cr - 0.5) + 0.02 * thread + 0.03 * slub
			mask[y * n + x] = cr
	var tex := _relief_rgba(h, mask, n, 9.0)
	_micro_cache["cloth"] = tex
	print("SKIN MICRO: cloth 256^2 in %d ms" % (Time.get_ticks_msec() - t0))
	return tex


## relief_normal with a mask in alpha, mipmapped (a normal map that averages to
## flat at distance is the right behaviour for micro-detail).
static func _relief_rgba(h: PackedFloat32Array, mask: PackedFloat32Array, n: int,
		gain: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var ym := posmod(y - 1, n)
		var yp := posmod(y + 1, n)
		for x in n:
			var xm := posmod(x - 1, n)
			var xp := posmod(x + 1, n)
			var dhdx := (h[y * n + xp] - h[y * n + xm]) * 0.5 * gain
			var dhdy := (h[yp * n + x] - h[ym * n + x]) * 0.5 * gain
			var v := Vector3(-dhdx, -dhdy, 1.0).normalized()
			img.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5,
				mask[y * n + x]))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func relief_normal(h: PackedFloat32Array, n: int, gain: float) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var ym := posmod(y - 1, n)
		var yp := posmod(y + 1, n)
		for x in n:
			var xm := posmod(x - 1, n)
			var xp := posmod(x + 1, n)
			var dhdx := (h[y * n + xp] - h[y * n + xm]) * 0.5 * gain
			var dhdy := (h[yp * n + x] - h[ym * n + x]) * 0.5 * gain
			var v := Vector3(-dhdx, -dhdy, 1.0).normalized()
			img.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Roughness field -> single-channel (R) roughness map. Godot MULTIPLIES the
## material's scalar `roughness` by this channel, so the caller sets the scalar
## to the CEILING of the range and the map scales down from there. Values are
## written to all three channels: a grey image mips identically in every
## channel, and it means the same texture can be re-used on the ORM channel
## selector without a surprise.
static func relief_rough(r: PackedFloat32Array, n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v := clampf(r[y * n + x], 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Attach relief to a finished material. No-op under `--gfx-v1`, which is what
## makes that arm honest. `rough` may be empty — plenty of surfaces want a
## normal and a single roughness number.
##
## `normal_scale` is the second half of the tuning: `gain` sets the shape of the
## slope in the texture, `normal_scale` sets how hard the engine leans on it.
## Splitting them matters because the texture is shared between materials that
## want the same relief at different strengths (brick at 3 m vs brick at 60 m).
static func attach_relief(m: BaseMaterial3D, normal_tex: ImageTexture,
		normal_scale: float, rough_tex: ImageTexture = null,
		rough_ceiling := -1.0) -> BaseMaterial3D:
	if v1():
		return m
	if normal_tex != null:
		m.normal_enabled = true
		m.normal_texture = normal_tex
		m.normal_scale = normal_scale
	if rough_tex != null:
		m.roughness_texture = rough_tex
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if rough_ceiling >= 0.0:
			m.roughness = rough_ceiling
	return m
