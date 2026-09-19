extends Node3D
## CEDAR CLIFF & THE DEACON ARTS DISTRICT — the south-west, off Juárez
## Boulevard. Map-concept region 4: craftsman blocks, a Latino main street,
## the forest creeping up from the Threefork Bottoms, and Gilead Bottoms'
## horse lots against the floodway's east levee.
##
## WORLD RULE 3 IS THE BRIEF. This neighbourhood is never the joke. It is
## built as a lived-in place: porches with chairs in them, papel picado over
## the street, a botánica window full of veladoras, a marquee that still says
## what is on Saturday, and the last horse lots in the floodplain. The ONLY
## satire on this ground is the gentrification frontier, and it is aimed at
## the developer: one COMING SOON board on a fenced lot at the boulevard's
## east end, one bandit sign on a pole, one oat-milk surcharge on a
## chalkboard. Institutions get the punchline; the block does not.
##
## CONTRACT (house law): visual-only build, one literal seed, MultiMeshes with
## a custom AABB (D-059), colliders only on masses a car must not pass
## through (house bodies, porches, storefronts, the Teatro, the barn, the
## boards). Nothing in the smoke corridor x[174,212] z[424,576]; nothing
## inside the Overflow campus (x 40..245, z 566..776) or the County General
## spur (x >= 330). Registered in the atlas (district `cliff`, places Teatro
## Estrella / Gilead Bottoms / the park, road Juárez Boulevard).
const SEED := 411907
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")
const TEX := preload("res://scripts/world/city_textures.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

# ---- the ground plan (world metres; north is -z) ----
const BLVD_X := 279.0                    # the north-south leg, downtown's spur
const BLVD_Z := 800.0                    # the east-west spine
const BLVD_W := 12.0
const BLVD_X0 := -480.0                  # west end, into Gilead Bottoms
const SIDE_X: Array[float] = [-300.0, -80.0]
const BACK_Z := 900.0
const SHOP_N_Z := 785.0                  # north row body centre (front at 790)
const SHOP_S_Z := 815.0                  # south row body centre (front at 810)
const TEATRO := Vector3(-100.0, 0.0, 783.0)
const CHURCH := Vector3(-347.0, 0.0, 770.0)
const PARK := Vector3(-190.0, 0.0, 870.0)
const LOFTS := Rect2(58.0, 808.0, 44.0, 54.0)      # the fenced empty lot
const GILEAD_X := Vector2(-498.0, -404.0)

# ---- the palettes ----
const CREAM := Color(0.90, 0.87, 0.78)
const TRIM := Color(0.94, 0.94, 0.91)
const SHINGLE := Color(0.24, 0.23, 0.22)
const TIMBER := Color(0.45, 0.35, 0.24)
const STEEL := Color(0.30, 0.32, 0.33)
const GALV := Color(0.58, 0.61, 0.63)
const DIRT := Color(0.42, 0.36, 0.27)
const BARN_RED := Color(0.44, 0.17, 0.14)
const STRAW := Color(0.80, 0.70, 0.36)
const GRASS := Color(0.31, 0.40, 0.23)
## Storefront brick/plaster tints — the four that actually repeat on a Texas
## main street built in the twenties and repainted ever since.
const SHOP_TINT: Array[Color] = [Color(0.72, 0.36, 0.28), Color(0.93, 0.89, 0.78),
	Color(0.36, 0.60, 0.58), Color(0.86, 0.69, 0.26)]
## House paints. Warm, specific, never a beige HOA sweep.
const HOUSE_PAINT: Array[Color] = [Color(0.64, 0.68, 0.55), Color(0.92, 0.89, 0.80),
	Color(0.78, 0.47, 0.34), Color(0.63, 0.75, 0.82), Color(0.66, 0.81, 0.71),
	Color(0.92, 0.82, 0.50)]
const FIESTA: Array[Color] = [Color(0.92, 0.24, 0.30), Color(0.98, 0.76, 0.18),
	Color(0.20, 0.62, 0.82), Color(0.36, 0.72, 0.36), Color(0.78, 0.34, 0.70),
	Color(0.98, 0.52, 0.16)]


var _rng := RandomNumberGenerator.new()
var _mat_asphalt: Material
var _mat_concrete: Material
var _mesh_cache: Dictionary = {}
var _unit_box := BoxMesh.new()
var _labels := 0
var _house_count := 0
var _shop_count := 0
# MultiMesh accumulators, one per archetype, flushed once at the end.
var _shop_xf: Array[Transform3D] = []       # storefront masses (brick, tinted)
var _shop_col: Array[Color] = []
var _plaster_xf: Array[Transform3D] = []    # parapets, sign bands, bulkheads
var _plaster_col: Array[Color] = []
var _glass_xf: Array[Transform3D] = []      # shop windows
var _awning_xf: Array[Transform3D] = []     # flat storefront awnings (coloured)
var _awning_col: Array[Color] = []
var _siding_xf: Array[Transform3D] = []     # house walls (painted lap siding)
var _siding_col: Array[Color] = []
var _trim_xf: Array[Transform3D] = []       # white trim: doors, sashes, rails
var _roof_xf: Array[Transform3D] = []       # house gable roofs (taper mesh)
var _shingle_xf: Array[Transform3D] = []    # porch roofs, flat dark boxes
var _timber_xf: Array[Transform3D] = []     # rail fence, posts, poles, barn trim
var _picket_xf: Array[Transform3D] = []     # low white picket fence
var _steel_xf: Array[Transform3D] = []      # sign posts, playground frame, poles
var _galv_xf: Array[Transform3D] = []       # chain-link posts
var _wire_xf: Array[Transform3D] = []       # chain-link mesh
var _trunk_xf: Array[Transform3D] = []      # tree trunks
var _canopy_xf: Array[Transform3D] = []
var _canopy_col: Array[Color] = []
var _paint_xf: Array[Transform3D] = []      # mural panels + motifs (coloured)
var _paint_col: Array[Color] = []
var _flag_xf: Array[Transform3D] = []       # papel picado flags
var _flag_col: Array[Color] = []
var _bulb_xf: Array[Transform3D] = []       # marquee bulbs (emissive)
var _horse_body_xf: Array[Transform3D] = []
var _horse_body_col: Array[Color] = []
var _horse_limb_xf: Array[Transform3D] = []
var _horse_limb_col: Array[Color] = []
var _straw_xf: Array[Transform3D] = []
var _grass_xf: Array[Transform3D] = []      # park green, pasture, yard patches
var _rubble_xf: Array[Transform3D] = []     # the half-demolished house


func build(city: Node3D) -> void:
	_rng.seed = SEED
	_unit_box.size = Vector3.ONE
	_mat_asphalt = city.get("mat_asphalt")
	_mat_concrete = city.get("mat_concrete")
	_roads()
	_main_street()
	_teatro()
	_papel_picado()
	_murals()
	_houses()
	_park()
	_church()
	_lofts_corner()
	_gilead_bottoms()
	_flush()
	print("CEDAR CLIFF: %d houses, %d storefronts, %d labels" % [
		_house_count, _shop_count, _labels])


# ========================== 1. THE RIGHT-OF-WAY ==============================
## Juárez Boulevard: a spur south off the downtown grid at x 279 (threaded
## between the Overflow campus's east fence at x 245 and County General's
## spur at x 330), then the long east-west run at z 800 to the floodway. Two
## side streets and one back street hang the blocks off it. Asphalt slabs,
## top at +0.02, the way every other district layer lays road.
func _roads() -> void:
	_solid(Vector3(BLVD_W, 0.08, 234.0), Vector3(BLVD_X, -0.02, 683.0), _mat_asphalt)
	var run := BLVD_X + BLVD_W * 0.5 - BLVD_X0
	_solid(Vector3(run, 0.08, BLVD_W), Vector3((BLVD_X0 + BLVD_X + BLVD_W * 0.5) * 0.5, -0.02, BLVD_Z),
		_mat_asphalt)
	for sx: float in SIDE_X:
		_solid(Vector3(8.0, 0.08, 240.0), Vector3(sx, -0.02, 820.0), _mat_asphalt)
	_solid(Vector3(580.0, 0.08, 8.0), Vector3(-190.0, -0.02, BACK_Z), _mat_asphalt)
	# Sidewalks along the commercial block only — the rest of the Cliff has the
	# narrow concrete ribbon the yards run straight into, which is honest.
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(170.0, 0.10, 4.0), Vector3(-148.0, -0.01, BLVD_Z + side * 9.0), _mat_concrete)
	_steel_xf.append(_axf(Vector3(0.18, 5.0, 0.18), Vector3(-72.0, 2.5, 794.0)))
	_plaster_xf.append(_axf(Vector3(4.8, 0.72, 0.10), Vector3(-72.0, 4.62, 794.0)))
	_plaster_col.append(Color(0.16, 0.32, 0.30))
	_label("JUÁREZ BLVD", Vector3(-72.0, 4.62, 794.08), 60, TRIM, 4.5, 0.0,
		SIGN.BLADE, 0.6)


# ============================ 2. THE MAIN STREET =============================
## Fourteen two-storey brick storefronts facing each other across the
## boulevard: parapet, flat awning, glass ground floor, a painted sign band
## with the name on it. The curb stays clear — parked_cars owns that lane.
const SHOPS_N: Array[String] = ["TAQUERÍA LA ESTRELLA", "BOTÁNICA SAN JUDAS",
	"PALETERÍA MICHOACANA", "LAVANDERÍA", "CARNICERÍA HERMANOS", "EL PATIO BAR",
	"CLIFF RECORDS"]
const SHOPS_S: Array[String] = ["FARMACIA", "ZAPATERÍA", "DEACON ARTS COFFEE",
	"PANADERÍA", "CLIFF CUTS"]


func _main_street() -> void:
	for i in SHOPS_N.size():
		_storefront(-196.0 + 13.0 * float(i), SHOP_N_Z, 0.0, SHOPS_N[i], i)
	for i in SHOPS_S.size():
		_storefront(-190.0 + 13.0 * float(i), SHOP_S_Z, PI, SHOPS_S[i], i + 3)
	# MERCADO REYES sits on the corner at the side street, modest and detached:
	# Book's family keeps a corner store, not an empire.
	_storefront(-94.0, SHOP_S_Z, PI, "MERCADO REYES", 1, 10.0, 6.4)
	_menu_board()
	_botanica_window()
	_chalkboard()
	_paleteria_cart()


## One storefront. `face` is 0 for the north row (front wall toward +z) and PI
## for the south row. Colliders on the mass only.
func _storefront(x: float, z: float, face: float, title: String, tint: int,
		w := 12.0, hgt := 7.0) -> void:
	var s := signf(cos(face))                    # +1 faces +z, -1 faces -z
	var front := z + s * 5.0
	var rot := Basis(Vector3.UP, face)
	var col := SHOP_TINT[tint % SHOP_TINT.size()]
	_shop_xf.append(_axf(Vector3(w, hgt, 10.0), Vector3(x, hgt * 0.5, z)))
	_shop_col.append(col)
	_collider(Vector3(w, hgt, 10.0), Vector3(x, hgt * 0.5, z))
	_plaster_xf.append(_axf(Vector3(w + 0.5, 0.95, 10.5), Vector3(x, hgt + 0.45, z)))
	_plaster_col.append(col.lightened(0.18))
	_plaster_xf.append(_axf(Vector3(w + 0.3, 1.25, 0.24), Vector3(x, hgt - 1.7, front + s * 0.1)))
	_plaster_col.append(CREAM)
	_glass_xf.append(_axf(Vector3(w - 1.6, 2.9, 0.14), Vector3(x, 2.05, front + s * 0.02)))
	_plaster_xf.append(_axf(Vector3(w - 1.6, 0.6, 0.20), Vector3(x, 0.3, front + s * 0.04)))
	_plaster_col.append(col.darkened(0.25))
	_awning_xf.append(Transform3D(rot * Basis(Vector3.RIGHT, 0.20)
		* Basis.from_scale(Vector3(w - 0.8, 0.16, 2.8)), Vector3(x, 3.85, front + s * 1.3)))
	_awning_col.append(FIESTA[(tint * 2 + 1) % FIESTA.size()])
	_trim_xf.append(_axf(Vector3(1.1, 2.4, 0.16), Vector3(x + w * 0.28, 1.2, front + s * 0.06)))
	_label(title, Vector3(x, hgt - 1.7, front + s * 0.24), 70, CREAM.darkened(0.55) \
		if col.get_luminance() > 0.5 else CREAM, w - 0.9, face, SIGN.FASCIA, 1.0)
	_shop_count += 1


## The taquería's menu is hand-lettered on the wall, because it always is.
func _menu_board() -> void:
	var x := -196.0
	_plaster_xf.append(_axf(Vector3(2.2, 1.7, 0.10), Vector3(x + 3.4, 2.1, 790.12)))
	_plaster_col.append(Color(0.96, 0.94, 0.88))
	_label("TACOS AL PASTOR 3\nBARBACOA 4\nAGUA FRESCA 2", Vector3(x + 3.4, 2.1, 790.20),
		30, Color(0.20, 0.16, 0.14), 2.0, 0.0, SIGN.HANDPAINT, 1.5)


## The botánica window: a shelf of veladoras behind the glass, which is what
## the window of a botánica actually is.
func _botanica_window() -> void:
	var x := -183.0
	for i in 9:
		_paint_xf.append(_axf(Vector3(0.22, 0.55, 0.22),
			Vector3(x - 4.0 + 1.0 * float(i), 2.35, 789.55)))
		_paint_col.append(FIESTA[i % FIESTA.size()])
	_label("VELADORAS · HIERBAS · LIMPIAS", Vector3(x, 3.30, 790.16), 26,
		Color(0.96, 0.92, 0.80), 5.4, 0.0, SIGN.HANDPAINT, 0.5)


## The one piece of satire on the block, and it is aimed at the price, not at
## anybody who lives here.
func _chalkboard() -> void:
	var x := -164.0
	_plaster_xf.append(_axf(Vector3(1.5, 1.9, 0.10), Vector3(x + 2.6, 1.15, 808.6)))
	_plaster_col.append(Color(0.13, 0.15, 0.14))
	_steel_xf.append(_axf(Vector3(1.2, 0.08, 0.6), Vector3(x + 2.6, 0.24, 808.6)))
	_label("OAT MILK\n+$1.50", Vector3(x + 2.6, 1.20, 808.53), 34,
		Color(0.92, 0.92, 0.88), 1.35, PI, SIGN.HANDPAINT, 1.6)


## The paletería cart parked outside the paletería, umbrella up.
func _paleteria_cart() -> void:
	var p := Vector3(-170.0, 0.0, 792.4)
	_plaster_xf.append(_axf(Vector3(1.7, 0.9, 0.95), p + Vector3(0, 0.78, 0)))
	_plaster_col.append(Color(0.94, 0.93, 0.90))
	_paint_xf.append(_axf(Vector3(1.8, 0.14, 1.05), p + Vector3(0, 1.28, 0)))
	_paint_col.append(FIESTA[0])
	for w: float in [-0.7, 0.7]:
		_steel_xf.append(_axf(Vector3(0.10, 0.34, 0.34), p + Vector3(w, 0.18, 0.0)))
	_steel_xf.append(_axf(Vector3(0.07, 1.5, 0.07), p + Vector3(0, 2.0, 0)))
	for i in 6:
		var a := float(i) * TAU / 6.0
		_paint_xf.append(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.42)
			* Basis.from_scale(Vector3(1.05, 0.05, 1.15)), p + Vector3(0, 2.62, 0)
			+ Vector3(sin(a), 0, cos(a)) * 0.52))
		_paint_col.append(FIESTA[i % FIESTA.size()])
	_label("PALETAS", p + Vector3(0, 1.05, 0.50), 30, Color(0.22, 0.18, 0.16),
		1.5, 0.0, SIGN.HANDPAINT, 0.4)


# ============================ 3. TEATRO ESTRELLA ============================
## The district's landmark and its promise: a blade sign you can navigate by
## from the far end of the boulevard, a marquee with this week's copy on it,
## a ticket booth and four doors that read as doors. Canon (naming bible §6):
## Teatro Estrella, on Juárez Boulevard.
const BLADE_TEXT := "T\nE\nA\nT\nR\nO\n·\nE\nS\nT\nR\nE\nL\nL\nA"


func _teatro() -> void:
	var x := TEATRO.x
	var front := 790.0
	_shop_xf.append(_axf(Vector3(20.0, 11.0, 14.0), Vector3(x, 5.5, TEATRO.z)))
	_shop_col.append(Color(0.88, 0.84, 0.74))
	_collider(Vector3(20.0, 11.0, 14.0), Vector3(x, 5.5, TEATRO.z))
	_plaster_xf.append(_axf(Vector3(20.6, 1.4, 14.6), Vector3(x, 11.6, TEATRO.z)))
	_plaster_col.append(Color(0.78, 0.30, 0.26))
	_shop_count += 1
	# The marquee: a slab over the sidewalk, copy on its face, bulbs on its lip.
	_plaster_xf.append(_axf(Vector3(15.0, 1.8, 3.4), Vector3(x, 6.4, front + 1.7)))
	_plaster_col.append(Color(0.95, 0.93, 0.86))
	_plaster_xf.append(_axf(Vector3(15.4, 0.3, 3.8), Vector3(x, 7.45, front + 1.7)))
	_plaster_col.append(Color(0.78, 0.30, 0.26))
	_steel_xf.append(_axf(Vector3(0.10, 2.6, 0.10), Vector3(x - 7.0, 8.6, front + 3.1)))
	_steel_xf.append(_axf(Vector3(0.10, 2.6, 0.10), Vector3(x + 7.0, 8.6, front + 3.1)))
	for i in 13:
		var bx := x - 7.2 + 1.2 * float(i)
		_bulb_xf.append(_axf(Vector3(0.26, 0.26, 0.26), Vector3(bx, 5.42, front + 3.38)))
	for j in 3:
		for side: float in [-1.0, 1.0]:
			_bulb_xf.append(_axf(Vector3(0.26, 0.26, 0.26),
				Vector3(x + side * 7.4, 5.42, front + 0.5 + 1.2 * float(j))))
	_label("HOY · CINE · LUCHA · QUINCEAÑERA SÁBADO", Vector3(x, 6.4, front + 3.42),
		90, Color(0.20, 0.17, 0.16), 14.0, 0.0, SIGN.MARQUEE, 1.5)
	_label("TEATRO ESTRELLA", Vector3(x, 9.5, front + 0.24), 90,
		Color(0.80, 0.22, 0.20), 16.0, 0.0, SIGN.CHANNEL, 1.5)
	# The blade: 9.5 m of vertical name, the thing you steer by.
	_plaster_xf.append(_axf(Vector3(0.35, 9.5, 2.8), Vector3(x, 13.6, front + 1.6)))
	_plaster_col.append(Color(0.78, 0.30, 0.26))
	_steel_xf.append(_axf(Vector3(0.5, 0.35, 3.1), Vector3(x, 18.5, front + 1.6)))
	_label(BLADE_TEXT, Vector3(x + 0.20, 13.6, front + 1.6), 75,
		Color(0.98, 0.94, 0.82), 2.5, PI * 0.5, SIGN.BLADE, 8.8)
	_label(BLADE_TEXT, Vector3(x - 0.20, 13.6, front + 1.6), 75,
		Color(0.98, 0.94, 0.82), 2.5, -PI * 0.5, SIGN.BLADE, 8.8)
	# The entry: a recessed lobby, a ticket booth, four doors.
	_plaster_xf.append(_axf(Vector3(3.0, 3.0, 1.8), Vector3(x, 1.5, front - 0.4)))
	_plaster_col.append(Color(0.72, 0.26, 0.24))
	_glass_xf.append(_axf(Vector3(2.2, 1.0, 0.12), Vector3(x, 2.1, front + 0.52)))
	for dx: float in [-5.2, -3.6, 3.6, 5.2]:
		_trim_xf.append(_axf(Vector3(1.4, 2.8, 0.16), Vector3(x + dx, 1.4, front + 0.08)))
	_label("TAQUILLA", Vector3(x, 3.15, front + 0.55), 26, Color(0.96, 0.92, 0.80),
		2.6, 0.0, SIGN.HANDPAINT, 0.4)


# ======================== 4. PAPEL PICADO + MURALS ==========================
## Strings across the boulevard between sidewalk poles, twelve cut flags each.
## No collider: you drive under them.
func _papel_picado() -> void:
	for i in 8:
		var x := -240.0 + 40.0 * float(i)
		for pz: float in [792.5, 807.5]:
			_timber_xf.append(_axf(Vector3(0.16, 6.8, 0.16), Vector3(x, 3.4, pz)))
		_timber_xf.append(_axf(Vector3(0.06, 0.06, 15.4), Vector3(x, 6.55, 800.0)))
		for k in 12:
			_flag_xf.append(_axf(Vector3(0.04, 0.50, 0.58),
				Vector3(x, 6.22, 793.3 + 1.22 * float(k))))
			_flag_col.append(FIESTA[(k + i) % FIESTA.size()])


## Three blank side walls get painted. Big flat panels, one motif each, two
## tones — the way a neighbourhood mural actually reads from a car.
func _murals() -> void:
	_mural(0, -202.1, -1.0, 785.0, 9.0, 5.4, 3.9)     # the sun, on the taquería
	_mural(1, -89.9, 1.0, 783.0, 11.0, 6.8, 4.6)      # the horse, on the Teatro
	_mural(2, -196.1, -1.0, 815.0, 9.0, 5.4, 3.9)     # the saint, on the farmacia


## `kind` 0 sun / 1 horse / 2 saint. Built in the wall plane at x = wx, facing
## `sgn`. All motif boxes ride in the same MultiMesh as the panel.
func _mural(kind: int, wx: float, sgn: float, cz: float, w: float, hgt: float,
		cy: float) -> void:
	var face := wx + sgn * 0.07
	var pal: Array[Color] = [Color(0.74, 0.33, 0.22), Color(0.14, 0.24, 0.40),
		Color(0.20, 0.42, 0.40)]
	_pbox(Vector2(w, hgt), 0.14, wx, cz, cy, 0.0, pal[kind])
	match kind:
		0:
			for r in 12:
				var a := float(r) * TAU / 12.0
				_pbox(Vector2(0.34, 1.5), 0.10, face, cz + sin(a) * 1.95,
					cy + cos(a) * 1.95, a, Color(0.97, 0.74, 0.22))
			for k in 3:
				_pbox(Vector2(2.3, 2.3), 0.10, face, cz, cy, float(k) * PI / 6.0,
					Color(0.97, 0.79, 0.28))
			for k in 3:
				_pbox(Vector2(1.3, 1.3), 0.12, face + sgn * 0.04, cz, cy,
					float(k) * PI / 6.0, Color(0.86, 0.40, 0.16))
		1:
			var cream := Color(0.94, 0.90, 0.78)
			_pbox(Vector2(3.4, 1.5), 0.10, face, cz, cy + 0.2, 0.0, cream)
			_pbox(Vector2(0.9, 1.9), 0.10, face, cz + 1.5, cy + 1.3, 0.42, cream)
			_pbox(Vector2(1.5, 0.66), 0.10, face, cz + 2.25, cy + 2.05, 0.26, cream)
			_pbox(Vector2(1.4, 0.34), 0.11, face + sgn * 0.03, cz + 2.55, cy + 1.85,
				0.20, Color(0.78, 0.34, 0.24))
			for lg in 4:
				var lx := cz - 1.3 + 0.9 * float(lg) + (0.5 if lg > 1 else 0.0)
				_pbox(Vector2(0.42, 1.9), 0.10, face, lx, cy - 1.3,
					-0.16 + 0.11 * float(lg), cream)
			_pbox(Vector2(0.34, 1.5), 0.10, face, cz - 1.9, cy + 0.7, -0.55, cream)
		_:
			var gold := Color(0.93, 0.78, 0.34)
			var pale := Color(0.94, 0.91, 0.84)
			_pbox(Vector2(2.4, 3.6), 0.10, face, cz, cy - 0.3, 0.0, pale)
			for k in 3:
				_pbox(Vector2(2.3, 2.3), 0.10, face, cz, cy + 1.5,
					float(k) * PI / 6.0, pale)
			_pbox(Vector2(1.5, 3.0), 0.11, face + sgn * 0.03, cz, cy - 0.5, 0.0, gold)
			for k in 3:
				_pbox(Vector2(1.4, 1.4), 0.11, face + sgn * 0.03, cz, cy + 1.0,
					float(k) * PI / 6.0, gold)
			for r in 10:
				var a := float(r) * TAU / 10.0
				_pbox(Vector2(0.20, 0.20), 0.12, face + sgn * 0.06,
					cz + sin(a) * 1.5, cy + 2.2 + cos(a) * 1.5, 0.0, gold)


## One painted box in a wall plane: `size` is (along z, along y), `ang` turns
## it inside that plane, `thick` is how far it stands off the wall.
func _pbox(size: Vector2, thick: float, wx: float, z: float, y: float,
		ang: float, col: Color) -> void:
	_paint_xf.append(Transform3D(Basis(Vector3.RIGHT, ang)
		* Basis.from_scale(Vector3(thick, size.y, size.x)), Vector3(wx, y, z)))
	_paint_col.append(col)


# ========================= 5. THE CRAFTSMAN BLOCKS ==========================
## Fifty-odd craftsman bungalows on 22 m lots, front-gabled, every one with a
## porch you could put a chair on — because on this side of town people sit on
## the porch, and a block that does not show that is not this block. Paint
## colours are warm and specific; the trim is white; a third of the yards have
## a tree and a third have a picket fence.
## Reserved ground the lots step around (x, z, w, d).
const RESERVED: Array[Rect2] = [
	Rect2(-362.0, 754.0, 30.0, 34.0),        # the church and its lawn
	Rect2(-222.0, 843.0, 64.0, 54.0),        # the park
	Rect2(-215.0, 778.0, 132.0, 44.0),       # the commercial core
	Rect2(52.0, 802.0, 56.0, 66.0),          # the Cliff Lofts lot
	Rect2(-506.0, 694.0, 106.0, 208.0),      # Gilead Bottoms
]
## Frontage runs: [fixed coord, yaw, from, to, step, axis] — axis 0 means the
## run marches along x at a fixed z, axis 1 along z at a fixed x.
const FRONTAGE: Array[Array] = [
	[780.0, 0.0, -430.0, -232.0, 22.0, 0],
	[820.0, PI, -430.0, -254.0, 22.0, 0],
	[820.0, PI, -56.0, 10.0, 22.0, 0],
	[880.0, 0.0, -420.0, -200.0, 22.0, 0],
	[920.0, PI, -420.0, -244.0, 22.0, 0],
	[-282.0, -PI * 0.5, 718.0, 762.0, 22.0, 1],
	[-282.0, -PI * 0.5, 830.0, 874.0, 22.0, 1],
	[-98.0, PI * 0.5, 718.0, 762.0, 22.0, 1],
	[-98.0, PI * 0.5, 830.0, 874.0, 22.0, 1],
]


func _houses() -> void:
	for run: Array in FRONTAGE:
		var fixed: float = run[0]
		var yaw: float = run[1]
		var t: float = run[2]
		while t <= float(run[3]) + 0.01:
			var pos := Vector3(t, 0.0, fixed) if int(run[5]) == 0 \
				else Vector3(fixed, 0.0, t)
			if _lot_free(pos, yaw):
				_house(pos, yaw)
			t += float(run[4])


## A lot is free when the house's world AABB clears every reserved rect.
func _lot_free(pos: Vector3, yaw: float) -> bool:
	var along_z := absf(cos(yaw)) > 0.5
	var hx := 5.0 if along_z else 8.5
	var hz := 8.5 if along_z else 5.0
	var box := Rect2(pos.x - hx, pos.z - hz, hx * 2.0, hz * 2.0)
	for r: Rect2 in RESERVED:
		if box.intersects(r):
			return false
	return true


## One bungalow, built in a local frame whose +z is the front, then yawed onto
## its lot. Colliders: the body and the porch volume, nothing else.
func _house(pos: Vector3, yaw: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var paint: Color = HOUSE_PAINT[_rng.randi_range(0, HOUSE_PAINT.size() - 1)]
	_siding_xf.append(Transform3D(rot * Basis.from_scale(Vector3(9.0, 4.0, 11.0)),
		pos + Vector3(0, 2.0, 0)))
	_siding_col.append(paint)
	_roof_xf.append(Transform3D(rot, pos + Vector3(0, 4.95, 0)))
	_shingle_xf.append(Transform3D(rot * Basis.from_scale(Vector3(9.6, 0.30, 3.4)),
		pos + rot * Vector3(0, 3.10, 7.0)))
	_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(9.0, 0.36, 2.8)),
		pos + rot * Vector3(0, 0.18, 6.9)))
	for px: float in [-3.5, 0.0, 3.5]:
		_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.28, 2.90, 0.28)),
			pos + rot * Vector3(px, 1.75, 8.15)))
	_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(9.0, 0.14, 0.16)),
		pos + rot * Vector3(0, 1.05, 8.32)))
	_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(9.0, 0.11, 0.13)),
		pos + rot * Vector3(0, 0.66, 8.32)))
	_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(1.15, 2.25, 0.14)),
		pos + rot * Vector3(0, 1.45, 5.58)))
	for wx: float in [-2.9, 2.9]:
		_trim_xf.append(Transform3D(rot * Basis.from_scale(Vector3(1.5, 1.3, 0.14)),
			pos + rot * Vector3(wx, 2.55, 5.58)))
	for c in _rng.randi_range(1, 2):
		_paint_xf.append(Transform3D(rot * Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5))
			* Basis.from_scale(Vector3(0.55, 0.86, 0.55)),
			pos + rot * Vector3(-2.4 + 4.6 * float(c), 0.78, 6.7)))
		_paint_col.append(FIESTA[_rng.randi_range(0, FIESTA.size() - 1)].lerp(CREAM, 0.35))
	_collider_b(Vector3(9.0, 4.0, 11.0), pos + Vector3(0, 2.0, 0), rot)
	_collider_b(Vector3(9.4, 3.3, 3.0), pos + rot * Vector3(0, 1.65, 6.95), rot)
	if _rng.randf() < 0.36:
		var a := pos + rot * Vector3(-10.0, 0, 11.4)
		_picket_run(a, pos + rot * Vector3(10.0, 0, 11.4))
	if _rng.randf() < 0.34:
		_tree(pos + rot * Vector3(_rng.randf_range(-6.0, 6.0), 0.0,
			_rng.randf_range(9.5, 13.0)))
	_house_count += 1


# ============================== 6. THE PARK =================================
## A green, a gazebo, four benches, a swing frame and six live oaks. Small,
## municipal, well used. No proper name is shipped: the bible has none for it
## yet, so the plaque is generic until one is ratified.
func _park() -> void:
	_grass_xf.append(_axf(Vector3(50.0, 0.06, 40.0), PARK + Vector3(0, 0.03, 0)))
	for i in 6:
		var a := float(i) * TAU / 6.0
		_timber_xf.append(_axf(Vector3(0.26, 3.0, 0.26),
			PARK + Vector3(sin(a) * 3.0, 1.55, cos(a) * 3.0)))
	_trim_xf.append(_axf(Vector3(7.4, 0.28, 7.4), PARK + Vector3(0, 0.14, 0)))
	_shingle_xf.append(_axf(Vector3(8.2, 0.9, 8.2), PARK + Vector3(0, 3.5, 0)))
	for b in 4:
		var ba := float(b) * TAU / 4.0 + 0.4
		var seat := PARK + Vector3(sin(ba) * 9.0, 0.0, cos(ba) * 9.0)
		var brot := Basis(Vector3.UP, ba)
		_trim_xf.append(Transform3D(brot * Basis.from_scale(Vector3(1.9, 0.12, 0.52)),
			seat + Vector3(0, 0.46, 0)))
		_trim_xf.append(Transform3D(brot * Basis.from_scale(Vector3(1.9, 0.5, 0.10)),
			seat + Vector3(0, 0.74, 0) + brot * Vector3(0, 0, -0.24)))
		for lz: float in [-0.75, 0.75]:
			_timber_xf.append(Transform3D(brot * Basis.from_scale(Vector3(0.14, 0.46, 0.44)),
				seat + Vector3(0, 0.23, 0) + brot * Vector3(lz, 0, 0)))
	var pg := PARK + Vector3(16.0, 0.0, -11.0)
	for sx: float in [-3.0, 3.0]:
		_steel_xf.append(_axf(Vector3(0.18, 3.0, 0.18), pg + Vector3(sx, 1.5, -1.0)))
		_steel_xf.append(_axf(Vector3(0.18, 3.0, 0.18), pg + Vector3(sx, 1.5, 1.0)))
	_steel_xf.append(_axf(Vector3(6.6, 0.20, 0.20), pg + Vector3(0, 2.95, 0)))
	for sw: float in [-1.2, 1.2]:
		_steel_xf.append(_axf(Vector3(0.06, 1.9, 0.06), pg + Vector3(sw, 1.95, 0)))
		_paint_xf.append(_axf(Vector3(0.7, 0.08, 0.32), pg + Vector3(sw, 0.98, 0)))
		_paint_col.append(FIESTA[2])
	for t in 6:
		var ta := float(t) * TAU / 6.0 + 0.7
		_tree(PARK + Vector3(sin(ta) * 19.0, 0.0, cos(ta) * 15.0))
	_label("PARQUE · CLOSES AT DUSK · NO GLASS", PARK + Vector3(-20.0, 1.1, 18.4),
		24, Color(0.92, 0.92, 0.88), 4.4, 0.0, SIGN.STENCIL, 0.5)
	_steel_xf.append(_axf(Vector3(4.6, 0.9, 0.12), PARK + Vector3(-20.0, 1.1, 18.5)))
	_steel_xf.append(_axf(Vector3(0.12, 1.2, 0.12), PARK + Vector3(-20.0, 0.6, 18.5)))


# ============================== 7. THE CHURCH ===============================
## Small, brick, one steeple, a monument sign on the boulevard side. Cedar
## Cliff's church is a storefront-sized congregation, not an Overflow arena —
## the contrast is the point and it is made by the massing, not by a joke.
func _church() -> void:
	_shop_xf.append(_axf(Vector3(10.0, 6.0, 16.0), CHURCH + Vector3(0, 3.0, 0)))
	_shop_col.append(Color(0.80, 0.76, 0.70))
	_collider(Vector3(10.0, 6.0, 16.0), CHURCH + Vector3(0, 3.0, 0))
	_roof_xf.append(Transform3D(Basis.from_scale(Vector3(0.98, 1.0, 1.33)),
		CHURCH + Vector3(0, 6.95, 0)))
	_plaster_xf.append(_axf(Vector3(4.2, 9.5, 4.2), CHURCH + Vector3(0, 4.75, 5.6)))
	_plaster_col.append(Color(0.86, 0.83, 0.76))
	_collider(Vector3(4.2, 9.5, 4.2), CHURCH + Vector3(0, 4.75, 5.6))
	_prop(MESH_KIT.taper(Vector3(4.6, 5.5, 4.6), Vector2(0.4, 0.4)),
		_flat(Color(0.30, 0.34, 0.38), 0.7), CHURCH + Vector3(0, 12.25, 5.6))
	_trim_xf.append(_axf(Vector3(0.24, 1.5, 0.24), CHURCH + Vector3(0, 15.75, 5.6)))
	_trim_xf.append(_axf(Vector3(0.90, 0.24, 0.24), CHURCH + Vector3(0, 15.95, 5.6)))
	for dx: float in [-1.0, 1.0]:
		_trim_xf.append(_axf(Vector3(1.05, 2.5, 0.16), CHURCH + Vector3(dx, 1.3, 7.78)))
	for wz: float in [-4.0, 0.0, 4.0]:
		for side: float in [-1.0, 1.0]:
			_trim_xf.append(_axf(Vector3(0.14, 2.6, 1.3),
				CHURCH + Vector3(side * 5.05, 3.2, wz)))
	_plaster_xf.append(_axf(Vector3(4.6, 1.7, 0.32), CHURCH + Vector3(0, 1.85, 13.0)))
	_plaster_col.append(Color(0.93, 0.91, 0.86))
	for mp: float in [-1.9, 1.9]:
		_timber_xf.append(_axf(Vector3(0.22, 2.0, 0.28), CHURCH + Vector3(mp, 1.0, 13.0)))
	_label("IGLESIA BAUTISTA DEL CLIFF", CHURCH + Vector3(0, 2.22, 13.18), 44,
		Color(0.26, 0.22, 0.34), 4.2, 0.0, SIGN.MARQUEE, 0.7)
	_label("DOMINGO 10", CHURCH + Vector3(0, 1.42, 13.18), 30,
		Color(0.30, 0.28, 0.26), 3.4, 0.0, SIGN.FLAT, 0.5)


# ======================= 8. THE GENTRIFICATION CORNER =======================
## The boulevard's east end: two houses came down, the lot is fenced, and the
## board on it is selling the neighbourhood back to people who do not live in
## it yet. This is the district's ONLY satire and it points at the developer.
func _lofts_corner() -> void:
	var x0 := LOFTS.position.x
	var z0 := LOFTS.position.y
	var x1 := LOFTS.end.x
	var z1 := LOFTS.end.y
	_fence_run(Vector3(x0, 0, z0), Vector3(x1, 0, z0))
	_fence_run(Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_fence_run(Vector3(x1, 0, z1), Vector3(x0, 0, z1))
	_fence_run(Vector3(x0, 0, z1), Vector3(x0, 0, z0))
	var bx := x0 + 22.0
	for pz: float in [-3.4, 3.4]:
		_timber_xf.append(_axf(Vector3(0.34, 6.4, 0.34), Vector3(bx + pz, 3.2, z0 + 2.6)))
	_plaster_xf.append(_axf(Vector3(8.0, 4.0, 0.30), Vector3(bx, 4.4, z0 + 2.6)))
	_plaster_col.append(Color(0.95, 0.94, 0.90))
	_plaster_xf.append(_axf(Vector3(8.2, 0.5, 0.40), Vector3(bx, 6.6, z0 + 2.6)))
	_plaster_col.append(Color(0.16, 0.30, 0.34))
	_label("COMING SOON\nTHE CLIFF LOFTS", Vector3(bx, 5.1, z0 + 2.42), 120,
		Color(0.16, 0.30, 0.34), 7.4, PI, SIGN.HOARDING, 2.0)
	_label("FROM THE $700s · A PIONEER VISION DEVELOPMENT",
		Vector3(bx, 3.35, z0 + 2.42), 40, Color(0.38, 0.40, 0.40), 7.4, PI,
		SIGN.PLAQUE, 0.7)
	# The bandit sign on the pole at the corner, leaning, because it always is.
	var lean := Basis(Vector3.FORWARD, 0.16)
	_timber_xf.append(Transform3D(lean * Basis.from_scale(Vector3(0.12, 2.4, 0.12)),
		Vector3(x0 - 6.0, 1.2, 791.0)))
	_plaster_xf.append(Transform3D(lean * Basis.from_scale(Vector3(2.6, 1.5, 0.07)),
		Vector3(x0 - 6.0, 2.4, 791.0)))
	_plaster_col.append(Color(0.97, 0.95, 0.30))
	_label("WE BUY\nHOUSES CASH\n214-555-0199", Vector3(x0 - 6.0, 2.4, 791.08),
		40, Color(0.12, 0.12, 0.12), 2.45, 0.0, SIGN.HANDPAINT, 1.4)
	# The house that already came down: a slab, one gable wall still standing.
	var h := Vector3(x0 + 30.0, 0.0, z0 + 36.0)
	_rubble_xf.append(_axf(Vector3(10.0, 0.30, 12.0), h + Vector3(0, 0.15, 0)))
	_rubble_xf.append(_axf(Vector3(9.2, 3.6, 0.34), h + Vector3(0, 1.8, -5.4)))
	_rubble_xf.append(_axf(Vector3(3.0, 1.6, 0.34), h + Vector3(-3.0, 4.3, -5.4)))
	for r in 14:
		var a := _rng.randf_range(0.0, TAU)
		var rr := _rng.randf_range(1.5, 7.5)
		_rubble_xf.append(Transform3D(Basis(Vector3.UP, a)
			* Basis(Vector3.RIGHT, _rng.randf_range(-0.6, 0.6))
			* Basis.from_scale(Vector3(_rng.randf_range(0.5, 1.8), 0.28,
				_rng.randf_range(0.4, 1.4))),
			h + Vector3(sin(a) * rr, 0.16, cos(a) * rr)))


# =========================== 9. GILEAD BOTTOMS ==============================
## Miss Earlene's six acres at the floodway's east rim: three horse lots on
## rail fence, a barn, a trough, a hay stack, two horses, and a hand-painted
## sign that says the same thing to the developer and to the county. Canon
## (naming bible §3): "the last horse lots in the floodplain". The boulevard
## dead-ends into it, which is the whole geography of the story.
func _gilead_bottoms() -> void:
	_grass_xf.append(_axf(Vector3(94.0, 0.05, 86.0), Vector3(-451.0, 0.025, 747.0)))
	_grass_xf.append(_axf(Vector3(94.0, 0.05, 86.0), Vector3(-451.0, 0.025, 853.0)))
	_lot_fence(Vector2(-498.0, 704.0), Vector2(-452.0, 790.0))
	_lot_fence(Vector2(-452.0, 704.0), Vector2(-404.0, 790.0))
	_lot_fence(Vector2(-498.0, 810.0), Vector2(-404.0, 896.0))
	# The barn, weathered red, gable end to the road. Collides.
	var barn := Vector3(-470.0, 0.0, 832.0)
	_siding_xf.append(_axf(Vector3(12.0, 6.0, 9.0), barn + Vector3(0, 3.0, 0)))
	_siding_col.append(BARN_RED)
	_collider(Vector3(12.0, 6.0, 9.0), barn + Vector3(0, 3.0, 0))
	_prop(MESH_KIT.taper(Vector3(12.8, 2.6, 9.6), Vector2(12.8, 0.6)),
		_flat(Color(0.36, 0.34, 0.31), 0.85), barn + Vector3(0, 7.2, 0))
	_trim_xf.append(_axf(Vector3(3.6, 4.2, 0.20), barn + Vector3(0, 2.1, -4.6)))
	_trim_xf.append(_axf(Vector3(12.2, 0.22, 0.22), barn + Vector3(0, 4.4, -4.6)))
	_timber_xf.append(_axf(Vector3(2.6, 0.70, 1.0), Vector3(-487.0, 0.35, 822.0)))
	_straw_xf.append(_axf(Vector3(4.2, 2.4, 3.2), Vector3(-440.0, 1.2, 848.0)))
	_straw_xf.append(_axf(Vector3(3.4, 1.1, 2.6), Vector3(-441.0, 2.9, 848.4)))
	# A gate in the north fence of the south lot, standing open. It is a hinge
	# with a story on it; a mission can close it one day.
	_timber_xf.append(_axf(Vector3(0.24, 2.0, 0.24), Vector3(-470.0, 1.0, 810.0)))
	_timber_xf.append(_axf(Vector3(0.24, 2.0, 0.24), Vector3(-458.0, 1.0, 810.0)))
	for g in 3:
		_timber_xf.append(Transform3D(Basis(Vector3.UP, -0.62)
			* Basis.from_scale(Vector3(5.6, 0.16, 0.12)),
			Vector3(-467.0, 0.6 + 0.5 * float(g), 811.6)))
	_horse(Vector3(-480.0, 0.0, 755.0), 0.62, Color(0.33, 0.20, 0.12))
	_horse(Vector3(-428.0, 0.0, 745.0), -1.15, Color(0.64, 0.63, 0.60))
	# The sign, on the boulevard's last posts.
	for sp: float in [-2.6, 2.6]:
		_timber_xf.append(_axf(Vector3(0.26, 3.4, 0.26), Vector3(-455.0 + sp, 1.7, 792.0)))
	_plaster_xf.append(_axf(Vector3(6.2, 2.0, 0.22), Vector3(-455.0, 2.6, 792.0)))
	_plaster_col.append(Color(0.90, 0.87, 0.76))
	_label("GILEAD BOTTOMS · EARLENE'S", Vector3(-455.0, 3.02, 792.14), 60,
		Color(0.28, 0.22, 0.16), 5.7, 0.0, SIGN.HANDPAINT, 0.8)
	_label("NO TRESPASSING   NO SELLING", Vector3(-455.0, 2.16, 792.14), 40,
		Color(0.62, 0.20, 0.16), 5.7, 0.0, SIGN.HANDPAINT, 0.55)


## Four rail runs around one lot.
func _lot_fence(a: Vector2, b: Vector2) -> void:
	_rail_run(Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y))
	_rail_run(Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y))
	_rail_run(Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y))
	_rail_run(Vector3(a.x, 0, b.y), Vector3(a.x, 0, a.y))


## A horse: an ellipsoid barrel, a canted neck, a muzzle, four legs, a tail.
## Static — a horse that never moves still reads as a horse at 40 m, and that
## is the job here.
func _horse(pos: Vector3, yaw: float, coat: Color) -> void:
	var rot := Basis(Vector3.UP, yaw)
	_horse_body_xf.append(Transform3D(rot * Basis.from_scale(Vector3(1.05, 1.25, 2.45)),
		pos + Vector3(0, 1.34, 0)))
	_horse_body_col.append(coat)
	_horse_body_xf.append(Transform3D(rot * Basis(Vector3.RIGHT, 0.40)
		* Basis.from_scale(Vector3(0.42, 0.46, 0.96)), pos + rot * Vector3(0, 2.32, 1.62)))
	_horse_body_col.append(coat.lightened(0.06))
	_horse_limb_xf.append(Transform3D(rot * Basis(Vector3.RIGHT, -0.58)
		* Basis.from_scale(Vector3(0.52, 1.40, 0.58)), pos + rot * Vector3(0, 1.92, 1.02)))
	_horse_limb_col.append(coat)
	for lg in 4:
		var sx := -0.40 if lg % 2 == 0 else 0.40
		var sz := -0.82 if lg < 2 else 0.86
		_horse_limb_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.20, 1.34, 0.22)),
			pos + rot * Vector3(sx, 0.67, sz)))
		_horse_limb_col.append(coat.darkened(0.18))
	_horse_limb_xf.append(Transform3D(rot * Basis(Vector3.RIGHT, 0.55)
		* Basis.from_scale(Vector3(0.16, 0.95, 0.18)), pos + rot * Vector3(0, 1.35, -1.32)))
	_horse_limb_col.append(coat.darkened(0.30))


# ================================ PLUMBING ==================================
## SHADOW POLICY (D-028): massing, roofs, trees and fences cast; paint, murals,
## flags, pickets, bulbs and the grass slabs do not.
func _flush() -> void:
	var brick := TEX.brick_material(Color(0.90, 0.87, 0.82))
	brick.vertex_color_use_as_albedo = true
	_mm(_shop_xf, _shop_col, brick, _unit_box, "CcShops", true)
	_mm(_plaster_xf, _plaster_col, _vtx_mat(0.82), _unit_box, "CcPlaster", true)
	_mm(_glass_xf, [], SHD.storefront_glass(true), _unit_box, "CcShopGlass", false)
	_mm(_awning_xf, _awning_col, _vtx_mat(0.78), _unit_box, "CcAwnings", true)
	_mm(_siding_xf, _siding_col, _siding_material(), _unit_box, "CcSiding", true)
	_mm(_trim_xf, [], _flat(TRIM, 0.72), _unit_box, "CcTrim", true)
	_mm(_roof_xf, [], _flat(SHINGLE, 0.92),
		MESH_KIT.taper(Vector3(10.2, 1.9, 12.2), Vector2(0.7, 12.2)), "CcRoofs", true)
	_mm(_shingle_xf, [], _flat(SHINGLE.lightened(0.08), 0.92), _unit_box, "CcPorchRoofs", true)
	_mm(_timber_xf, [], _flat(TIMBER, 0.92), _unit_box, "CcTimber", true)
	_mm(_picket_xf, [], _flat(TRIM.darkened(0.08), 0.85), _unit_box, "CcPickets", false)
	_mm(_steel_xf, [], _flat(STEEL, 0.55), _unit_box, "CcSteel", true)
	var galv := _flat(GALV, 0.45)
	galv.metallic = 0.4
	_mm(_galv_xf, [], galv, _unit_box, "CcGalv", true)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.45, 0.47, 0.48, 0.4)
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire.roughness = 0.6
	wire.metallic = 0.3
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(_wire_xf, [], wire, _unit_box, "CcFenceMesh", false)
	_mm(_trunk_xf, [], _flat(Color(0.30, 0.25, 0.20), 0.95),
		MESH_KIT.round_limb(0.26, 0.17, 1.0, 7), "CcTrunks", true)
	_mm(_canopy_xf, _canopy_col, _vtx_mat(0.95),
		MESH_KIT.canopy(1.0, 8, 12, 19, 0.20, 0.08), "CcCanopies", true)
	_mm(_paint_xf, _paint_col, _vtx_mat(0.88), _unit_box, "CcPaint", false)
	var flag := _vtx_mat(0.80)
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(_flag_xf, _flag_col, flag, _unit_box, "CcPapelPicado", false)
	var bulb := _flat(Color(0.99, 0.90, 0.66), 0.5)
	bulb.emission_enabled = true
	bulb.emission = Color(0.99, 0.90, 0.66)
	bulb.emission_energy_multiplier = 1.0
	_mm(_bulb_xf, [], bulb, MESH_KIT.sphere(0.5, 6, 10), "CcMarqueeBulbs", false)
	_mm(_horse_body_xf, _horse_body_col, _vtx_mat(0.72),
		MESH_KIT.sphere(0.5, 7, 12), "CcHorseBodies", true)
	_mm(_horse_limb_xf, _horse_limb_col, _vtx_mat(0.72), _unit_box, "CcHorseLimbs", true)
	_mm(_straw_xf, [], _flat(STRAW, 0.98), _unit_box, "CcStraw", true)
	_mm(_grass_xf, [], _flat(GRASS, 0.97), _unit_box, "CcGreens", false)
	_mm(_rubble_xf, [], _flat(Color(0.56, 0.53, 0.49), 0.95), _unit_box, "CcRubble", true)


## Painted lap siding: a 2.56 m triplanar tile of 160 mm boards with a shadow
## line under each lap. Instance colour is the paint, so fifty-one houses in
## six colours cost one material and one image.
func _siding_material() -> StandardMaterial3D:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		var lap := y % 8
		var v := 1.0
		if lap == 7:
			v = 0.64
		elif lap == 0:
			v = 1.06
		for x in 128:
			var g := v * (0.985 + 0.03 * float((x * 7 + y * 3) % 5) / 4.0)
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 2.56
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.90
	m.vertex_color_use_as_albedo = true
	return m


## A live oak: one tapered trunk plus three canopy lobes, the same recipe the
## landmark layer uses, so the Cliff's street trees match the county's.
func _tree(base: Vector3) -> void:
	var h := _rng.randf_range(3.0, 4.4)
	_trunk_xf.append(Transform3D(Basis(Vector3.RIGHT, _rng.randf_range(-0.05, 0.05))
		* Basis.from_scale(Vector3(1.0, h, 1.0)), base + Vector3(0, h * 0.5, 0)))
	var s := _rng.randf_range(0.92, 1.20)
	for lobe in 3:
		var off := Vector3(_rng.randf_range(-1.0, 1.0), h + _rng.randf_range(0.2, 1.1),
			_rng.randf_range(-1.0, 1.0))
		_canopy_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(3.5, 2.8, 3.5) * s * _rng.randf_range(0.78, 1.0)),
			base + off))
		var g := _rng.randf_range(0.86, 1.06)
		_canopy_col.append(Color(0.30 * g, 0.40 * g, 0.22 * g))


## Three-rail horse fence: posts every 3 m, rails at 0.45 / 0.88 / 1.30 m.
## No collider — a rail fence is not a mass a car must not pass through.
func _rail_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var run_len := d.length()
	if run_len < 0.1:
		return
	var rot := Basis(Vector3.UP, atan2(d.x, d.z) + PI * 0.5)
	var mid := (a + b) * 0.5
	for r in 3:
		_timber_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 0.13, 0.10)),
			mid + Vector3(0, 0.45 + 0.425 * float(r), 0)))
	var n := int(run_len / 3.0)
	for i in n + 1:
		_timber_xf.append(_axf(Vector3(0.17, 1.55, 0.17),
			a.lerp(b, float(i) / float(maxi(n, 1))) + Vector3(0, 0.775, 0)))


## Low white picket, front lot line, two rails and a paling every 1.1 m.
func _picket_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var run_len := d.length()
	if run_len < 0.1:
		return
	var rot := Basis(Vector3.UP, atan2(d.x, d.z) + PI * 0.5)
	var mid := (a + b) * 0.5
	for r in 2:
		_picket_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 0.08, 0.07)),
			mid + Vector3(0, 0.38 + 0.36 * float(r), 0)))
	var n := int(run_len / 1.1)
	for i in n + 1:
		_picket_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.09, 0.92, 0.07)),
			a.lerp(b, float(i) / float(maxi(n, 1))) + Vector3(0, 0.46, 0)))


## Chain-link, with a collider: this one IS a boundary a car should feel.
func _fence_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var run_len := d.length()
	var rot := Basis(Vector3.UP, atan2(d.x, d.z) + PI * 0.5)
	var mid := (a + b) * 0.5
	_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 2.2, 0.05)),
		mid + Vector3(0, 1.15, 0)))
	_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 0.05, 0.05)),
		mid + Vector3(0, 2.3, 0)))
	var n := int(run_len / 8.0)
	for i in n + 1:
		_galv_xf.append(_axf(Vector3(0.13, 2.6, 0.13),
			a.lerp(b, float(i) / float(maxi(n, 1))) + Vector3(0, 1.3, 0)))
	_collider_b(Vector3(run_len, 2.6, 0.15), mid + Vector3(0, 1.3, 0), rot)


func _solid(size: Vector3, origin: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.IDENTITY, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_box(size)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _collider(size: Vector3, origin: Vector3) -> void:
	_collider_b(size, origin, Basis.IDENTITY)


func _collider_b(size: Vector3, origin: Vector3, basis: Basis) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


## A one-off mesh (the spire, the barn roof) — cheaper as a MeshInstance than
## as a MultiMesh of one.
func _prop(mesh: Mesh, mat: Material, origin: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = origin
	add_child(mi)


func _axf(size: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)


func _label(text: String, pos: Vector3, fsize: int, col: Color, max_w: float,
		yaw: float, style: int = SIGN.FLAT, max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)
	_labels += 1


func _flat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _vtx_mat(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


func _shared_box(size: Vector3) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]


## One MultiMesh per archetype. The AABB is set from the instance origins
## (D-059: a script-built MultiMesh can carry an EMPTY one and draw nothing);
## instance colours go in linear (they reach the shader raw).
func _mm(xf: Array[Transform3D], cols: Array[Color], mat: Material,
		mesh: Mesh, label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	var bounds := AABB(xf[0].origin, Vector3.ZERO)
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		bounds = bounds.expand(xf[i].origin)
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i].srgb_to_linear())
	mm.custom_aabb = bounds.grow(30.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
