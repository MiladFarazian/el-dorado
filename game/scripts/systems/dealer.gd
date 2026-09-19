extends Node
## BOONE TRUCKS — the lot, the note, and the man who wrote it (naming bible §7).
##
## Wade "The Bullet" Boone sells trucks on the I-3 north frontage at ninety-six
## months and zero down. The satire is SUBURBAN CREDIT: the note, the fine
## print, and the draft that comes out of your account whether or not the week
## went your way. Wade is the tragicomic end of it — a Friday-night-football
## legend who is himself leveraged to the roofline and genuinely, warmly means
## "Appreciate you" every single time. NOBODY WHO SIGNS IS EVER THE JOKE.
## LONGHORN WRECKER & RECOVERY ("We Own That Too") is the other end of it, and
## it is the same company Book drives for — which is the whole point.
##
## THE LOOP: walk up to a vehicle on the front line, TAP G to sign the note
## ($0 down, granted immediately, drafted daily), or HOLD G to pay cash. Two
## returned drafts and Longhorn takes it back; ninety-six paid and the title
## clears. Buying is the only way into the fleet besides the rig you own.
##
## CONTRACT. This file owns `scripts/systems/dealer.gd` and
## `data/mechanics/dealer.json` and edits nothing else. Every peer is optional
## and reached through `main.systems` via `_peer()`; every main.gd hook is
## called through `has_method()`/`call()` so the system boots with none of them
## present. Visual dressing is built once in setup() — no _process cost — and
## every runtime MultiMesh sets `custom_aabb` from its instance origins (D-059:
## a script-built MultiMesh with an empty AABB draws NOTHING). Nothing is built
## inside the smoke corridor x[174,212] z[424,576]; the lot is 400 m west of it.

const DATA_PATH := "res://data/mechanics/dealer.json"
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

# ============================== THE LOT ======================================
## Lot rect x -180..-40, z -110..-44 (prairie, north of the frontage band
## z -36..-24). The Middlington water tower at (-300,-140) is 120 m clear west.
const LOT_CENTER := Vector3(-110.0, 0.0, -77.0)
const LOT_SIZE := Vector2(140.0, 66.0)        # x by z
const LOT_TOP := 0.02                          # prairie slab top is -0.02
const DRIVE_X := -110.0
const DRIVE_W := 10.0
const DRIVE_Z0 := -44.0                        # lot's south edge
const DRIVE_Z1 := -36.0                        # frontage clear band
const DRIVE_TOP := 0.03                        # freeway apron top is +0.01
const EXIT_POINT := Vector3(-110.0, 1.6, -40.0)   # clears the tallest ride (Brisket, 1.351 m)
const SHOWROOM_SIZE := Vector3(24.0, 6.0, 12.0)
const SHOWROOM_CENTER := Vector3(-145.0, 3.0, -100.0)
const GLASS_INSET := 1.0                       # glass is this much narrower per side
const PYLON_X := -98.0
const PYLON_Z := -47.0
const PYLON_H := 14.0
const BOARD_SIZE := Vector3(9.6, 6.6, 0.45)
const LIGHT_H := 9.0
const DISPLAY_X := -70.0                       # the front line, lot's east half
const DISPLAY_Z0 := -58.0                      # first bumper, working north

# -- Palette ------------------------------------------------------------------
const ASPHALT := Color(0.13, 0.13, 0.14)
const DRIVE_PAINT := Color(0.16, 0.16, 0.17)
const WALL := Color(0.87, 0.85, 0.80)          # metal-building cream
const TRIM := Color(0.62, 0.15, 0.12)          # Boone red, same red as the wrecker
const GLASS := Color(0.06, 0.09, 0.11)
const STEEL := Color(0.46, 0.47, 0.50)
const SIGN_FACE := Color(0.96, 0.94, 0.88)
const SIGN_INK := Color(0.10, 0.10, 0.11)
const LAMP := Color(1.0, 0.94, 0.78)
const PENNANT: Array[Color] = [
	Color(0.85, 0.16, 0.13), Color(0.95, 0.80, 0.20), Color(0.16, 0.34, 0.66),
	Color(0.92, 0.92, 0.90), Color(0.20, 0.56, 0.32),
]

# ============================== PUBLIC =======================================
signal vehicle_granted(path: String)
signal vehicle_repossessed(path: String)

## Live notes. Each: {path: String, balance: int, monthly: int, paid: int,
## missed: int}. Plain Dictionaries so save_load can round-trip them with
## set("notes", array) and no schema translation.
var notes: Array = []

# ============================== STATE ========================================
var main_ref: Node = null
var cfg: Dictionary = {}
var _disabled := false
var _stock: Array[Dictionary] = []     # {path, price, name, monthly, body, pos}
var _ui: CanvasLayer = null
var _prompt: Label = null
var _near := -1
var _hold := 0.0
var _bought_on_hold := false
var _day_t := 0.0
var _pending: Array[String] = []       # repossessed, waiting for the player to walk away
var _local_owned: Array[String] = []   # mirror of main.owned_paths; the truth if it is absent
var _rng := RandomNumberGenerator.new()
var _mesh_cache: Dictionary = {}
var _unit: BoxMesh = null


# ============================== SETUP ========================================
func setup(main: Node) -> void:
	main_ref = main
	_rng.seed = 0xB00 + 0x17E
	if bool(main.get("smoke_mode")):
		_disabled = true
		set_physics_process(false)
		return                     # smoke gate: no lot, no stock, no UI
	_load_cfg()
	_build_stock()
	_build_lot()
	_build_showroom()
	_build_pylon()
	_build_pennants()
	_build_lot_lights()
	_build_display_vehicles()
	_build_slot_cards()
	_build_ui()


func _load_cfg() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		cfg = parsed


func _n(key: String, def: float) -> float:
	var v: Variant = cfg.get(key, def)
	return float(v) if (v is float or v is int) else def


func _i(key: String, def: int) -> int:
	var v: Variant = cfg.get(key, def)
	return int(v) if (v is float or v is int) else def


## A string from a sub-dictionary, e.g. _s("app", "paid", "…"). An empty
## `section` reads the top level, so every copy lookup is one call shape.
func _s(section: String, key: String, def: String) -> String:
	var d: Dictionary = cfg
	if section != "":
		var sub: Variant = cfg.get(section, null)
		if not (sub is Dictionary):
			return def
		d = sub
	var v: Variant = d.get(key, def)
	return v if v is String else def


func _list(section: String, key: String) -> Array:
	var d: Dictionary = cfg
	if section != "":
		var sub: Variant = cfg.get(section, null)
		if not (sub is Dictionary):
			return []
		d = sub
	var v: Variant = d.get(key, [])
	return v if v is Array else []


func _pick(pool: Array) -> String:
	if pool.is_empty():
		return ""
	return str(pool[_rng.randi_range(0, pool.size() - 1)])


## {token} substitution — named and order-free, unlike positional %.
func _fill(text: String, fields: Dictionary) -> String:
	var out := text
	for k: Variant in fields:
		out = out.replace("{%s}" % str(k), str(fields[k]))
	return out


## $28,700 — the number the sign has to be able to show you.
func _usd(amount: int) -> String:
	var neg := amount < 0
	var digits := str(absi(amount))
	var grouped := ""
	var n := digits.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-" if neg else "") + grouped


# ============================== THE STOCK ====================================
## Read every purchasable profile once: its name, its price, the monthly the
## note works out to, and the geometry the display body needs. The wrecker is
## Book's own rig and is never on the lot.
func _build_stock() -> void:
	var months := _i("note_months", 96)
	var apr := _n("note_apr_total", 1.31)
	var gap := _n("display_gap_m", 5.0)
	var z := DISPLAY_Z0
	var prev_half := 0.0
	for row: Variant in _stock_rows():
		if not (row is Dictionary):
			continue
		var d: Dictionary = row
		var path := str(d.get("path", ""))
		var prof := _profile(path)
		if prof.is_empty():
			continue
		var price := int(d.get("price", 0))
		var size := _size_of(prof)
		var half := size.z * 0.5
		if prev_half > 0.0:
			z -= prev_half + gap + half
		prev_half = half
		_stock.append({
			"path": path,
			"price": price,
			"name": str(prof.get("name", "A TRUCK")).to_upper(),
			"monthly": int(ceil(float(price) * apr / float(maxi(months, 1)))),
			"profile": prof,
			"size": size,
			"pos": Vector3(DISPLAY_X, 0.0, z),
			"body": null,
		})


func _stock_rows() -> Array:
	var v: Variant = cfg.get("stock", [])
	return v if v is Array else []


func _profile(path: String) -> Dictionary:
	if path == "" or not ResourceLoader.exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _pf(prof: Dictionary, key: String, def: float) -> float:
	var v: Variant = prof.get(key, def)
	return float(v) if (v is float or v is int) else def


func _size_of(prof: Dictionary) -> Vector3:
	var v: Variant = prof.get("body_size", null)
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3(2.0, 1.4, 4.6)


func _paint_of(prof: Dictionary, key: String, def: Color) -> Color:
	var v: Variant = prof.get(key, null)
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return def


## STATIC RIDE, THE SAME ARITHMETIC THE REAL CAR USES (raycast_vehicle.gd).
## Total compression m*g/2k splits across the axles by the doubled com_forward
## lever; the body origin sits that far above the ground. Verified against each
## profile's own `_tuning_math`: Brisket 1.351, Vantage 0.873, Slab 0.940.
## Returns [ride, front_hub_y, rear_hub_y] in body-local metres.
func _ride_of(prof: Dictionary) -> Array:
	var rest := _pf(prof, "suspension_rest", 0.4)
	var hard_y := _pf(prof, "hardpoint_height", -0.3)
	var radius := _pf(prof, "wheel_radius", 0.38)
	var wb_f := _pf(prof, "wheelbase_front", 1.4)
	var wb_r := _pf(prof, "wheelbase_rear", 1.4)
	var wb_sum := maxf(wb_f + wb_r, 0.001)
	var share := clampf((wb_r + 2.0 * _pf(prof, "com_forward", 0.0)) / wb_sum, 0.05, 0.95)
	var comp := _pf(prof, "mass", 1500.0) * 9.81 \
		/ maxf(2.0 * _pf(prof, "spring_rate", 45000.0), 1.0)
	var comp_f := clampf(comp * share, 0.0, rest)
	var comp_r := clampf(comp * (1.0 - share), 0.0, rest)
	var hub_f := hard_y - (rest - comp_f)
	var hub_r := hard_y - (rest - comp_r)
	return [radius - (hub_f + hub_r) * 0.5, hub_f, hub_r]


# ============================== THE LOT, BUILT ===============================
## Asphalt. Both slabs carry collision because both are DRIVING SURFACE: the
## prairie under them tops out at -0.02 and the freeway apron at +0.01, so a
## visual-only slab would let the wheels sink into it.
func _build_lot() -> void:
	_solid(Vector3(LOT_SIZE.x, 1.0, LOT_SIZE.y),
		Vector3(LOT_CENTER.x, LOT_TOP - 0.5, LOT_CENTER.z), _flat(ASPHALT, 0.96))
	_solid(Vector3(DRIVE_W, 1.0, DRIVE_Z1 - DRIVE_Z0),
		Vector3(DRIVE_X, DRIVE_TOP - 0.5, (DRIVE_Z0 + DRIVE_Z1) * 0.5),
		_flat(DRIVE_PAINT, 0.94))
	# Two hand-painted lane arrows on the drive: OUT is the only direction a
	# car ever leaves here, which is also the joke.
	var paint := _flat(Color(0.86, 0.84, 0.72), 0.9)
	for i in 2:
		_box(Vector3(0.5, 0.02, 3.0), Vector3(DRIVE_X + (1.8 if i == 0 else -1.8),
			DRIVE_TOP + 0.01, DRIVE_Z0 + 3.0), paint)


## The showroom: a 24 x 6 x 12 metal building on the lot's north side with a
## dark glass front standing proud of the wall, a red fascia band, and the name
## across it. One collider (the building); everything applied to it is visual.
func _build_showroom() -> void:
	_solid(SHOWROOM_SIZE, SHOWROOM_CENTER, _flat(WALL, 0.88))
	var front := SHOWROOM_CENTER.z + SHOWROOM_SIZE.z * 0.5
	var glass := _flat(GLASS, 0.18)
	glass.metallic = 0.55
	_box(Vector3(SHOWROOM_SIZE.x - GLASS_INSET * 2.0, 3.8, 0.35),
		Vector3(SHOWROOM_CENTER.x, 2.5, front + 0.20), glass)
	_box(Vector3(SHOWROOM_SIZE.x + 0.2, 1.6, 0.30),
		Vector3(SHOWROOM_CENTER.x, 5.2, front - 0.05), _flat(TRIM, 0.82))
	_box(Vector3(SHOWROOM_SIZE.x + 0.6, 0.4, SHOWROOM_SIZE.z + 0.6),
		Vector3(SHOWROOM_CENTER.x, SHOWROOM_SIZE.y + 0.2, SHOWROOM_CENTER.z),
		_flat(STEEL, 0.6))
	# Mullions: four uprights so the glass reads as a storefront, not a screen.
	var mull := _flat(STEEL, 0.5)
	for i in 4:
		var mx := SHOWROOM_CENTER.x - 8.4 + float(i) * 5.6
		_box(Vector3(0.22, 3.9, 0.42), Vector3(mx, 2.5, front + 0.22), mull)
	# A Label3D reads from +z at yaw 0; the road is south (larger z), so the
	# fascia faces +z at yaw 0 and needs no rotation at all.
	_label(_s("sign", "showroom", "BOONE TRUCKS"),
		Vector3(SHOWROOM_CENTER.x, 5.45, front + 0.16), 220, SIGN_FACE,
		SHOWROOM_SIZE.x - 3.0, 0.0, SIGN.CHANNEL, 1.05)
	_label(_s("sign", "showroom_sub", ""),
		Vector3(SHOWROOM_CENTER.x, 4.62, front + 0.16), 90, TRIM,
		SHOWROOM_SIZE.x - 6.0, 0.0, SIGN.PLAQUE, 0.42)


## THE PYLON. Fourteen metres of it, because the note is the product and the
## terms are the advertisement: "96 MONTHS · $0 DOWN · YOUR SIGNATURE IS YOUR
## CREDIT" is legible from the frontage at speed, which is exactly the point.
func _build_pylon() -> void:
	_solid(Vector3(1.1, PYLON_H, 1.1), Vector3(PYLON_X, PYLON_H * 0.5, PYLON_Z),
		_flat(TRIM, 0.8))
	var mid := PYLON_H - 3.6
	_box(Vector3(BOARD_SIZE.x + 0.6, BOARD_SIZE.y + 0.6, 0.40),
		Vector3(PYLON_X, mid, PYLON_Z), _flat(TRIM, 0.8))
	_box(Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.44),
		Vector3(PYLON_X, mid, PYLON_Z + 0.10), _flat(SIGN_FACE, 0.75))
	var face_z := PYLON_Z + 0.42
	_label(_s("sign", "name", "BOONE TRUCKS"),
		Vector3(PYLON_X, mid + 2.05, face_z), 260, SIGN_INK,
		BOARD_SIZE.x - 0.7, 0.0, SIGN.CHANNEL, 2.1)
	_label(_s("sign", "tagline", "APPRECIATE YOU!"),
		Vector3(PYLON_X, mid - 0.05, face_z), 190, TRIM,
		BOARD_SIZE.x - 0.7, 0.0, SIGN.FASCIA, 1.45)
	var terms := SIGN.balance(_s("sign", "terms", ""), 2)
	_label(terms, Vector3(PYLON_X, mid - 2.00, face_z), 110, SIGN_INK,
		BOARD_SIZE.x - 0.5, 0.0, SIGN.HOARDING, 1.75)


# ============================== PENNANTS =====================================
## Triangle flags on a sagging wire — the universal signal for "this lot needs
## you more than you need it". Two MultiMeshes (wire segments, flags), both
## with `custom_aabb` set from the instance origins (D-059: a script-built
## MultiMesh reports an EMPTY AABB and draws nothing without it).
const PENNANT_POLE_H := 5.2
const PENNANT_SAG := 0.9
const FLAGS_PER_RUN := 11

func _build_pennants() -> void:
	var row_a: Array[Vector3] = []
	for x: float in [-174.0, -146.0, -118.0, -102.0, -74.0, -46.0]:
		row_a.append(Vector3(x, 0.0, -47.0))
	var row_b: Array[Vector3] = []
	for z: float in [-52.0, -70.0, -88.0, -106.0]:
		row_b.append(Vector3(-46.0, 0.0, z))
	var wire_xf: Array[Transform3D] = []
	var flag_xf: Array[Transform3D] = []
	var flag_col: Array[Color] = []
	var pole_mat := _flat(STEEL, 0.7)
	for run: Array[Vector3] in [row_a, row_b]:
		for p: Vector3 in run:
			_solid(Vector3(0.20, PENNANT_POLE_H, 0.20),
				Vector3(p.x, PENNANT_POLE_H * 0.5, p.z), pole_mat)
		for i in run.size() - 1:
			_pennant_run(run[i], run[i + 1], wire_xf, flag_xf, flag_col)
	var wire_mat := _flat(Color(0.14, 0.14, 0.15), 0.8)
	_mm(wire_xf, [], wire_mat, "BooneWire", false)
	var flag_mat := _flat(Color.WHITE, 0.82)
	flag_mat.vertex_color_use_as_albedo = true
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(flag_xf, flag_col, flag_mat, "BoonePennants", false)


## One catenary-ish run between two poles: short wire segments plus a flag
## hanging off each interior sample point.
func _pennant_run(a: Vector3, b: Vector3, wire: Array[Transform3D],
		flags: Array[Transform3D], cols: Array[Color]) -> void:
	var pts: Array[Vector3] = []
	for i in FLAGS_PER_RUN + 1:
		var t := float(i) / float(FLAGS_PER_RUN)
		var p := a.lerp(b, t)
		p.y = PENNANT_POLE_H - PENNANT_SAG * sin(t * PI)
		pts.append(p)
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := p1 - p0
		if seg.length() < 0.001:
			continue
		var rot := Basis.looking_at(seg.normalized(), Vector3.UP)
		wire.append(Transform3D(rot * Basis.from_scale(Vector3(0.035, 0.035, seg.length())),
			(p0 + p1) * 0.5))
		if i == 0:
			continue
		var hang := p0 - Vector3(0.0, 0.30, 0.0)
		var yaw := atan2(seg.x, seg.z) + _rng.randf_range(-0.22, 0.22)
		flags.append(Transform3D(
			Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.02, 0.46, 0.34)), hang))
		cols.append(PENNANT[_rng.randi_range(0, PENNANT.size() - 1)])


# ============================== LOT LIGHTS ===================================
## Six poles, two heads apiece. Emissive lamp faces only — no OmniLights: the
## rendering budget owns the light count, and a lot at night reads off the
## fixtures plus the streetlight_glow layer that already exists.
func _build_lot_lights() -> void:
	var pole_mat := _flat(STEEL, 0.7)
	var lamp_mat := _flat(LAMP, 0.4)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = LAMP
	lamp_mat.emission_energy_multiplier = 1.6
	# x -128, never -112: the exit lane runs x -115..-105 and a 9 m pole two
	# metres off it is a defect, not dressing.
	for spot: Vector2 in [Vector2(-168, -58), Vector2(-128, -58), Vector2(-58, -58),
			Vector2(-168, -98), Vector2(-128, -98), Vector2(-58, -98)]:
		_solid(Vector3(0.28, LIGHT_H, 0.28), Vector3(spot.x, LIGHT_H * 0.5, spot.y),
			pole_mat)
		_box(Vector3(3.2, 0.16, 0.24), Vector3(spot.x, LIGHT_H - 0.25, spot.y), pole_mat)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(1.05, 0.22, 0.62),
				Vector3(spot.x + side * 1.35, LIGHT_H - 0.48, spot.y), lamp_mat)


# ============================== THE FRONT LINE ===============================
## One frozen display body per purchasable profile, nose to the road, built by
## the SAME `vehicle_body_builder` the hero cars use and handed the SAME wheel
## stations and static ride heights — so the truck on the lot is visually the
## truck you drive off it, not a stand-in. NOT in `towable`, NOT in `drivable`,
## NOT in `civilian`: the stock cannot be hooked or jacked, only bought.
func _build_display_vehicles() -> void:
	for i in _stock.size():
		var row: Dictionary = _stock[i]
		var body := _make_display(row)
		if body == null:
			continue
		row["body"] = body
		_stock[i] = row
	_refresh_display()


func _make_display(row: Dictionary) -> RigidBody3D:
	var prof: Dictionary = row.get("profile", {})
	if prof.is_empty():
		return null
	var size: Vector3 = row.get("size", Vector3(2.0, 1.4, 4.6))
	var geom := _ride_of(prof)
	var ride: float = geom[0]
	var radius := _pf(prof, "wheel_radius", 0.38)
	var width := _pf(prof, "wheel_width", 0.28)
	var half_track := _pf(prof, "track_width", 1.7) * 0.5
	var wb_f := _pf(prof, "wheelbase_front", 1.4)
	var wb_r := _pf(prof, "wheelbase_rear", 1.4)
	var body := RigidBody3D.new()
	body.name = "BooneStock_%s" % str(prof.get("plate_text", "LOT")).replace(" ", "")
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.mass = _pf(prof, "mass", 1500.0)
	body.set_meta("carjack_has_driver", false)
	body.set_meta("boone_stock", row.get("path", ""))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var vis := Node3D.new()
	body.add_child(vis)
	BODY_BUILDER.build(vis, str(prof.get("body_style", "box")), size,
		_paint_of(prof, "color", Color(0.7, 0.2, 0.2)),
		str(prof.get("door_text", "")), {
			"hero": true,
			"badge": str(prof.get("name", "")),
			"plate": str(prof.get("plate_text", "")),
			"wheel_z": Vector2(-wb_f, wb_r),
			"wheel_r": radius,
			"wheel_y": Vector2(geom[1], geom[2]),
			"wheel_x": half_track,
			"wheel_w": width,
		})
	_display_wheels(body, prof, ride)
	# Nose to the road: the frontage is south (+z), so the car faces +z.
	var pos: Vector3 = row.get("pos", LOT_CENTER)
	body.transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP),
		Vector3(pos.x, LOT_TOP + ride, pos.z))
	add_child(body)
	return body


## Four wheels at the real stations, rim discs on the outer faces — the same
## trick raycast_vehicle uses so a Slab on the lot still runs gold wire.
func _display_wheels(body: RigidBody3D, prof: Dictionary, ride: float) -> void:
	var radius := _pf(prof, "wheel_radius", 0.38)
	var width := _pf(prof, "wheel_width", 0.28)
	var half_track := _pf(prof, "track_width", 1.7) * 0.5
	var stations := [Vector2(-1.0, -_pf(prof, "wheelbase_front", 1.4)),
		Vector2(1.0, -_pf(prof, "wheelbase_front", 1.4)),
		Vector2(-1.0, _pf(prof, "wheelbase_rear", 1.4)),
		Vector2(1.0, _pf(prof, "wheelbase_rear", 1.4))]
	var tire := CylinderMesh.new()
	tire.top_radius = radius
	tire.bottom_radius = radius
	tire.height = width
	tire.radial_segments = 20
	var tire_mat := _flat(Color(0.07, 0.07, 0.08), 0.95)
	var rim := CylinderMesh.new()
	rim.top_radius = radius * 0.62
	rim.bottom_radius = radius * 0.62
	rim.height = 0.03
	rim.radial_segments = 18
	var rim_mat := _flat(_paint_of(prof, "rim_color", Color(0.72, 0.73, 0.76)), 0.35)
	rim_mat.metallic = 0.55
	for s: Vector2 in stations:
		var y := radius - ride
		var hub := Vector3(s.x * half_track, y, s.y)
		var w := MeshInstance3D.new()
		w.mesh = tire
		w.material_override = tire_mat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = hub
		body.add_child(w)
		var d := MeshInstance3D.new()
		d.mesh = rim
		d.material_override = rim_mat
		d.rotation_degrees = Vector3(0, 0, 90)
		d.position = hub + Vector3(s.x * (width * 0.5 + 0.016), 0.0, 0.0)
		body.add_child(d)


## The lot shows what it still has. A bought vehicle is off the line; a
## repossessed one is back on it, in the same slot, same paint.
func _refresh_display() -> void:
	for row: Dictionary in _stock:
		var body: Variant = row.get("body", null)
		if not (body is RigidBody3D) or not is_instance_valid(body):
			continue
		var b: RigidBody3D = body
		var on_lot := not _owns(str(row.get("path", "")))
		b.visible = on_lot
		b.collision_layer = 1 if on_lot else 0
		b.collision_mask = 1 if on_lot else 0
		var sale: Variant = row.get("card_sale", null)
		var sold: Variant = row.get("card_sold", null)
		if sale is Label3D and is_instance_valid(sale):
			(sale as Label3D).visible = on_lot
		if sold is Label3D and is_instance_valid(sold):
			(sold as Label3D).visible = not on_lot


# ============================== SLOT CARDS ===================================
## The windshield card on a stand in front of each unit: the cash price in big
## type and the monthly underneath it in bigger type, which is the entire sales
## philosophy of this lot rendered as typography.
func _build_slot_cards() -> void:
	var months := _i("note_months", 96)
	for i in _stock.size():
		var row: Dictionary = _stock[i]
		var size: Vector3 = row.get("size", Vector3(2.0, 1.4, 4.6))
		var pos: Vector3 = row.get("pos", LOT_CENTER)
		var front := pos.z + size.z * 0.5 + 1.1
		_solid(Vector3(0.10, 1.05, 0.10), Vector3(pos.x, 0.52, front), _flat(STEEL, 0.7))
		_box(Vector3(1.45, 0.95, 0.07), Vector3(pos.x, 1.42, front),
			_flat(SIGN_FACE, 0.78))
		_box(Vector3(1.55, 0.14, 0.09), Vector3(pos.x, 1.96, front), _flat(TRIM, 0.8))
		var on_sale := "$%s\n$%s/mo × %d" % [_usd(int(row.get("price", 0))),
			_usd(int(row.get("monthly", 0))), months]
		var a := SIGN.make(on_sale, SIGN.HOARDING, SIGN_INK, 1.30, 0.80, 120)
		a.position = Vector3(pos.x, 1.42, front + 0.06)
		add_child(a)
		var b := SIGN.make("SOLD\nAPPRECIATE YOU!", SIGN.MARQUEE, TRIM, 1.30, 0.80, 120)
		b.position = Vector3(pos.x, 1.42, front + 0.06)
		b.visible = false
		add_child(b)
		row["card_sale"] = a
		row["card_sold"] = b
		_stock[i] = row


# ============================== PROMPT UI ====================================
const PROMPT_FONT_SIZE := 21
const PROMPT_MARGIN := 136
const PROMPT_COLOR := Color(0.96, 0.93, 0.82)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, PROMPT_MARGIN)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", PROMPT_FONT_SIZE)
	_prompt.add_theme_color_override("font_color", PROMPT_COLOR)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: never eat mouse look
	_prompt.visible = false
	_ui.add_child(_prompt)


func _show_prompt(text: String) -> void:
	if _prompt == null or not is_instance_valid(_prompt):
		return
	_prompt.text = text
	_prompt.visible = true


func _hide_prompt() -> void:
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.visible = false


## The line under the reticle for whichever unit you are standing at.
func _prompt_for(row: Dictionary) -> String:
	var path := str(row.get("path", ""))
	var months := _i("note_months", 96)
	var fields := {
		"name": str(row.get("name", "")),
		"price": _usd(int(row.get("price", 0))),
		"monthly": _usd(int(row.get("monthly", 0))),
		"months": months,
	}
	var note := _note_for(path)
	if not note.is_empty():
		fields["paid"] = int(note.get("paid", 0))
		fields["missed"] = int(note.get("missed", 0))
		return _fill(_s("prompt", "on_note", ""), fields)
	if _owns(path):
		return _fill(_s("prompt", "owned", ""), fields)
	if _hold > 0.0:
		return _fill(_s("prompt", "signing", ""), fields)
	return _fill(_s("prompt", "buy", ""), fields)


# ============================== THE LOOP =====================================
func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	_tick_notes(delta)
	_tick_pending()
	_tick_counter(delta)


## Standing at a unit, on foot, inside `buy_range_m`. Driving hides the prompt
## outright — you cannot sign a note through a windscreen.
func _tick_counter(delta: float) -> void:
	if _stock.is_empty():
		return
	if not bool(main_ref.get("on_foot")):
		_near = -1
		_hold = 0.0
		_bought_on_hold = false
		_hide_prompt()
		return
	var actor := _actor()
	if actor == null:
		_hide_prompt()
		return
	# Range is measured to the vehicle's FOOTPRINT, not to its centre point: a
	# 5.8 m Brisket's nose is 2.9 m from its own origin, so a centre-point test
	# would put a player standing at the front bumper out of range of the truck
	# they are looking at.
	var range_m := _n("buy_range_m", 3.5)
	var best := -1
	var best_d := range_m
	for i in _stock.size():
		var row: Dictionary = _stock[i]
		var pos: Vector3 = row.get("pos", LOT_CENTER)
		var size: Vector3 = row.get("size", Vector3(2.0, 1.4, 4.6))
		var off := Vector2(actor.global_position.x - pos.x,
			actor.global_position.z - pos.z)
		var d := Vector2(maxf(absf(off.x) - size.x * 0.5, 0.0),
			maxf(absf(off.y) - size.z * 0.5, 0.0)).length()
		if d < best_d:
			best_d = d
			best = i
	if best != _near:
		_near = best
		_hold = 0.0
		_bought_on_hold = false
	if _near < 0:
		_hide_prompt()
		return
	_tick_input(delta, _stock[_near])
	_show_prompt(_prompt_for(_stock[_near]))


## TAP G signs the note. HOLD G for `hold_seconds` pays cash. One key, two very
## different relationships with Wade Boone.
func _tick_input(delta: float, row: Dictionary) -> void:
	if not InputMap.has_action("interact"):
		return
	var path := str(row.get("path", ""))
	if _owns(path):
		_hold = 0.0
		return
	if Input.is_action_pressed("interact"):
		_hold += delta
		if not _bought_on_hold and _hold >= _n("hold_seconds", 1.2):
			_bought_on_hold = true
			buy_cash(path)
		return
	if Input.is_action_just_released("interact"):
		if not _bought_on_hold and _hold > 0.0:
			sign_note(path)
		_hold = 0.0
		_bought_on_hold = false


# ============================== BUYING =======================================
## PUBLIC: pay the cash price outright. Refuses, in Wade's voice, if short.
func buy_cash(path: String) -> bool:
	var idx := _index_of(path)
	if idx < 0 or _owns(path):
		print("DEALER: buy_cash refused for %s (stock idx %d, owned %s)" % [path, idx, _owns(path)])
		return false
	var row: Dictionary = _stock[idx]
	var price := int(row.get("price", 0))
	var repo := _peer("repo_board")
	var have := 0
	if repo != null:
		var m: Variant = repo.get("money")
		if m is int or m is float:
			have = int(m)
	if have < price:
		_flash(_s("", "cash_short", "Wade says: 'Cash is for people who don't trust themselves.'"))
		_say(_s("", "wade_speaker", "WADE BOONE"),
			_s("", "cash_short_line", "Cash is for people who don't trust themselves."))
		return false
	# GRANT FIRST, THEN DEBIT. main.grant_vehicle refuses a path that is not in
	# profile_paths, and a player who pays $28,700 for a refusal is the one kind
	# of joke this lot is not allowed to make.
	if not _grant(path):
		print("DEALER: buy_cash — main refused the grant for %s" % path)
		return false
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", -price, "BOONE TRUCKS")
	_card_for(row, true, 0)
	_say(_s("", "wade_speaker", "WADE BOONE"), _pick(_list("", "wade_cash_lines")))
	return true


## PUBLIC: sign. $0 down, the vehicle is yours today, the note starts tomorrow.
func sign_note(path: String) -> bool:
	var idx := _index_of(path)
	if idx < 0 or _owns(path):
		return false
	var row: Dictionary = _stock[idx]
	var monthly := int(row.get("monthly", 0))
	if not _grant(path):
		return false
	notes.append({
		"path": path,
		"balance": int(row.get("price", 0)),
		"monthly": monthly,
		"paid": 0,
		"missed": 0,
	})
	_card_for(row, false, monthly)
	_say(_s("app", "speaker", "BOONE FINANCIAL"),
		_fill(_s("app", "signed", ""), {"monthly": _usd(monthly)}))
	_say(_s("", "wade_speaker", "WADE BOONE"), _pick(_list("", "wade_lines")), 6.0)
	return true


## Hand the keys over. main.gd owns the fleet list and the spawner; both hooks
## are optional, so a tree without them still sells you the truck and keeps its
## own record until the producer wires them up.
func _grant(path: String) -> bool:
	var granted := true
	if main_ref.has_method("grant_vehicle"):
		var r: Variant = main_ref.call("grant_vehicle", path)
		granted = (r is bool and bool(r)) or r == null
	if not granted:
		return false
	if not _local_owned.has(path):
		_local_owned.append(path)
	_place_new_vehicle(path)
	_refresh_display()
	vehicle_granted.emit(path)
	return true


## On foot: it is waiting for you at the exit, nose to the frontage. Driving:
## it swaps in under you the way Tab does, carrying transform and velocity so
## the trade-in never launches you into the prairie.
func _place_new_vehicle(path: String) -> void:
	if not main_ref.has_method("_spawn_vehicle"):
		return
	var driving := not bool(main_ref.get("on_foot"))
	var t := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), EXIT_POINT)
	var lv := Vector3.ZERO
	var av := Vector3.ZERO
	if driving:
		var cur: Variant = main_ref.get("vehicle")
		if cur is RigidBody3D and is_instance_valid(cur):
			var c: RigidBody3D = cur
			t = c.global_transform
			t.origin += Vector3(0, 0.5, 0)
			lv = c.linear_velocity
			av = c.angular_velocity
	main_ref.call("_spawn_vehicle", path)
	var v: Variant = main_ref.get("vehicle")
	if not (v is RigidBody3D) or not is_instance_valid(v):
		return
	var nv: RigidBody3D = v
	nv.global_transform = t
	nv.linear_velocity = lv
	nv.angular_velocity = av


## The contract card. The NOTE row is where the satire lands: the monthly is
## the number Wade says out loud, and the interest is the number he does not.
func _card_for(row: Dictionary, cash: bool, monthly: int) -> void:
	var kit := _peer("mission_kit")
	if kit == null or not kit.has_method("card"):
		return
	var months := _i("note_months", 96)
	var price := int(row.get("price", 0))
	var rows: Array = []
	if cash:
		rows = [["PRICE", "$" + _usd(price)], ["PAID", "CASH IN FULL"], ["OWED", "$0"]]
	else:
		var interest := monthly * months - price
		rows = [
			["PRICE", "$" + _usd(price)],
			["NOTE", "$%s/mo × %d · $%s in interest" % [_usd(monthly), months, _usd(interest)]],
			["DOWN", "$0"],
		]
	kit.call("card", _s("card", "title", "APPRECIATE YOU!"),
		_fill(_s("card", "subtitle", ""), {"name": str(row.get("name", ""))}), rows, "")


# ============================== THE NOTE =====================================
## BOONE FINANCIAL drafts once per in-game day. Counted off play time rather
## than off sky_weather's clock so the draft is identical headless, in a probe,
## and on a machine where the sun is not moving.
func _tick_notes(delta: float) -> void:
	if notes.is_empty():
		return
	_day_t += delta
	var day := _n("day_seconds", 600.0)
	if _day_t < day:
		return
	_day_t -= day
	note_tick_now()


## PUBLIC (probe/debug): run a draft day right now.
func note_tick_now() -> void:
	var months := _i("note_months", 96)
	var limit := _i("miss_limit", 2)
	var repo := _peer("repo_board")
	var speaker := _s("app", "speaker", "BOONE FINANCIAL")
	var take: Array[String] = []
	for i in notes.size():
		var note: Variant = notes[i]
		if not (note is Dictionary):
			continue
		var d: Dictionary = note
		var monthly := int(d.get("monthly", 0))
		var have := 0
		if repo != null:
			var m: Variant = repo.get("money")
			if m is int or m is float:
				have = int(m)
		if have >= monthly:
			if repo != null and repo.has_method("add_money"):
				repo.call("add_money", -monthly, "BOONE FINANCIAL")
			d["paid"] = int(d.get("paid", 0)) + 1
			d["balance"] = maxi(int(d.get("balance", 0)) - monthly, 0)
			_say(speaker, _fill(_s("app", "paid", ""), {
				"monthly": _usd(monthly), "left": months - int(d["paid"])}))
		else:
			d["missed"] = int(d.get("missed", 0)) + 1
			_say(speaker, _missed_line(int(d["missed"])))
		notes[i] = d
		if int(d.get("paid", 0)) >= months:
			take.append("+" + str(d.get("path", "")))
		elif int(d.get("missed", 0)) >= limit:
			take.append("-" + str(d.get("path", "")))
	for entry: String in take:
		var path := entry.substr(1)
		if entry.begins_with("+"):
			_clear_title(path)
		else:
			_repossess(path)


func _missed_line(missed: int) -> String:
	var pool := _list("app", "missed")
	if missed >= 1 and missed <= pool.size():
		return str(pool[missed - 1])
	return _fill(_s("app", "missed_more", ""), {"missed": missed})


## Ninety-six of ninety-six. The only line Wade gets to say without a crack in it.
func _clear_title(path: String) -> void:
	_drop_note(path)
	_say(_s("app", "speaker", "BOONE FINANCIAL"),
		_s("app", "title_clear", "TITLE CLEAR. Appreciate you."))


## PUBLIC (probe/debug): take it back now, whatever the note says.
func repossess_now(path: String) -> bool:
	if _note_for(path).is_empty() and not _owns(path):
		return false
	_repossess(path)
	return true


## LONGHORN comes for it. If you are sitting in it, nothing visibly happens —
## they are not going to fight you for it on the shoulder of I-3. They wait
## until you are out of it and thirty metres away, and then it is not there.
func _repossess(path: String) -> void:
	# main.revoke_vehicle answers false when there is nothing to take (the
	# wrecker, or a rig that is not on the list). The paper is void either way,
	# but nobody gets the recovery line for a car that was never there.
	if main_ref.has_method("revoke_vehicle"):
		var r: Variant = main_ref.call("revoke_vehicle", path)
		if r is bool and not bool(r):
			_drop_note(path)
			_local_owned.erase(path)
			_refresh_display()
			return
	_local_owned.erase(path)
	if _is_current(path):
		if not _pending.has(path):
			_pending.append(path)
		_say(_s("repo", "speaker", "LONGHORN · RECOVERY"),
			_s("repo", "warn", ""))
		return
	_finish_repossession(path)


## The deferred half: on foot and far enough away, the space where it was
## parked has the wrecker in it instead. We Own That Too.
func _tick_pending() -> void:
	if _pending.is_empty():
		return
	if not bool(main_ref.get("on_foot")):
		return
	var actor := _actor()
	var cur: Variant = main_ref.get("vehicle")
	var far := true
	if actor != null and cur is RigidBody3D and is_instance_valid(cur):
		far = actor.global_position.distance_to((cur as RigidBody3D).global_position) \
			>= _n("repo_distance_m", 30.0)
	if not far:
		return
	for path: String in _pending.duplicate():
		_finish_repossession(path)
	_pending.clear()


func _finish_repossession(path: String) -> void:
	if _is_current(path):
		_swap_to_wrecker()
	_drop_note(path)
	_local_owned.erase(path)
	_pending.erase(path)
	_refresh_display()
	_say(_s("repo", "speaker", "LONGHORN · RECOVERY"),
		_s("repo", "line", "YOUR VEHICLE HAS BEEN RECOVERED. WE OWN THAT TOO."), 6.0)
	vehicle_repossessed.emit(path)


## Your rig is what is left. That is the joke and it is also the mercy.
func _swap_to_wrecker() -> void:
	if not main_ref.has_method("_spawn_vehicle"):
		return
	var wrecker := _wrecker_path()
	if wrecker == "":
		return
	var t := Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP), EXIT_POINT)
	var cur: Variant = main_ref.get("vehicle")
	if cur is RigidBody3D and is_instance_valid(cur):
		t = (cur as RigidBody3D).global_transform
		t.origin += Vector3(0, 0.4, 0)
	main_ref.call("_spawn_vehicle", wrecker)
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v):
		(v as RigidBody3D).global_transform = t


func _wrecker_path() -> String:
	var paths: Variant = main_ref.get("profile_paths")
	if paths is Array:
		for p: Variant in paths as Array:
			if str(p).contains("wrecker"):
				return str(p)
	return "res://data/vehicles/wrecker.json"


func _drop_note(path: String) -> void:
	for i in range(notes.size() - 1, -1, -1):
		var n: Variant = notes[i]
		if n is Dictionary and str((n as Dictionary).get("path", "")) == path:
			notes.remove_at(i)


func _note_for(path: String) -> Dictionary:
	for n: Variant in notes:
		if n is Dictionary and str((n as Dictionary).get("path", "")) == path:
			return n
	return {}


# ============================== INVENTORY ====================================
## PUBLIC: the lot as data — [{path, name, price, monthly, owned}].
func inventory() -> Array:
	var out: Array = []
	for row: Dictionary in _stock:
		var path := str(row.get("path", ""))
		out.append({
			"path": path,
			"name": str(row.get("name", "")),
			"price": int(row.get("price", 0)),
			"monthly": int(row.get("monthly", 0)),
			"owned": _owns(path),
		})
	return out


## main.owned_paths is the truth when it exists; `_local_owned` mirrors it so a
## tree without the hook still behaves.
func _owns(path: String) -> bool:
	var owned: Variant = main_ref.get("owned_paths") if main_ref != null else null
	if owned is Array:
		for p: Variant in owned as Array:
			if str(p) == path:
				return true
		return _local_owned.has(path)
	return _local_owned.has(path)


func _index_of(path: String) -> int:
	for i in _stock.size():
		if str((_stock[i] as Dictionary).get("path", "")) == path:
			return i
	return -1


func _is_current(path: String) -> bool:
	var v: Variant = main_ref.get("vehicle")
	if not (v is RigidBody3D) or not is_instance_valid(v):
		return false
	return str((v as Node).get("profile_path")) == path


# ============================== PEERS ========================================
func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null


func _actor() -> Node3D:
	if main_ref == null:
		return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var key := "character" if bool(main_ref.get("on_foot")) else "vehicle"
	var v: Variant = main_ref.get(key)
	if v is Node3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


func _say(speaker: String, line: String, seconds := 4.5) -> void:
	if line == "":
		return
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("say"):
		kit.call("say", speaker, line, seconds)


func _flash(text: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("flash"):
		repo.call("flash", text)


# ============================== BUILD HELPERS ================================
## Static box WITH collision — used only for masses a car must not pass
## through, plus the two asphalt slabs that ARE the driving surface.
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


## Visual-only box: glass, fascia, mullions, lamp heads, lane paint. Nothing
## here is a collider, because nothing here is in a car's way.
func _box(size: Vector3, origin: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_box(size)
	mi.material_override = mat
	mi.position = origin
	add_child(mi)


func _shared_box(size: Vector3) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]


func _flat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


## Measured-glyph fit (sign_kit.gd). A Label3D reads from +z at yaw 0 and the
## frontage is south of the lot, so every sign here faces +z unrotated.
func _label(text: String, pos: Vector3, fsize: int, col: Color, max_w: float,
		yaw: float, style: int, max_h: float) -> void:
	if text == "":
		return
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)


## D-059: a script-built MultiMesh reports an EMPTY AABB and is culled to
## nothing. `custom_aabb` is computed from the instance origins here, always.
func _mm(xf: Array[Transform3D], cols: Array[Color], mat: Material,
		label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = _unit_box()
	mm.instance_count = xf.size()
	var aabb := AABB(xf[0].origin, Vector3.ZERO)
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
		aabb = aabb.expand(xf[i].origin)
	mm.custom_aabb = aabb.grow(1.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _unit_box() -> BoxMesh:
	if _unit == null:
		_unit = BoxMesh.new()
		_unit.size = Vector3.ONE
	return _unit
