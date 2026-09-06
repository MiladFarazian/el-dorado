extends Node
## THE CANDYLAND STRIP — the Slow Lane verb from ratified story canon.
## On the southernmost downtown E-W street (centre z=477, x 300..780) speed
## loses respect and crawling with style earns it: hold 3-9 m/s to bank
## escalating RESPECT ticks through repo_board. Driving the Candyland Slab
## doubles every tick; night doubles it again (slabs come out at night).
## Exceeding 13 m/s kills the combo but costs nothing — the strip teaches,
## it doesn't punish. Markers are pure visuals (no colliders). No RNG used.

signal strip_tick(amount: int)

# ============================== TUNABLES =====================================
const BAND_X := Vector2(300.0, 780.0)      # strip extent along the street
const BAND_Z := Vector2(464.0, 490.0)      # southernmost E-W roadway band
const BAND_MAX_Y := 8.0                    # sanity: ignore anything airborne
const CRUISE_SPEED := Vector2(3.0, 9.0)    # scoring window (m/s)
const MOVE_MIN := 2.0                      # below this you are "stopped"
const BREAK_SPEED := 13.0                  # above this the combo dies
const TICK_SECONDS := 5.0                  # unbroken slow-roll per tick
const TICKS_PER_STEP := 4                  # base escalates +1 every 4 ticks
const TICK_CAP := 5                        # base tick never exceeds this
const STILL_GRACE := 8.0                   # parked-AFK guard (s)
const SLAB_NAME := "Candyland Slab"        # style ride: doubles every tick
const FLASH_SECONDS := 2.5
const FLASH_BIG_SECONDS := 4.5             # first strip entry of the session
const FADE_SECONDS := 2.0                  # status line fade after leaving
# --- THE STRIP'S LOOK (rebuilt for defect D-013) -----------------------------
# It used to be four 1.4 x 14 x 1.4 fully-opaque magenta pillars at both ends,
# emissive at 2.2 against a 1.05 HDR bloom threshold, plus eight proud candy
# kerb blocks at 1.4. From 300 m up they were still hard pink sticks and they
# out-read every real landmark in the city. The zone is real gameplay, so the
# ZONE stayed and only the PRESENTATION changed: a cruise strip should read as
# a piece of STREET — paint on the asphalt, a lit kerb line, gate furniture at
# knee height — never as a column.
const ROAD_Z := 477.0                      # strip street centreline
const SIGN := preload("res://scripts/world/sign_kit.gd")
const ROAD_HALF := 11.0                    # white edge lines sit at +/- 11 m
const KERB_Z: Array[float] = [464.0, 490.0]      # block faces, 0.2 m kerb
const PAINT_Y := 0.047                     # 1 mm over city_dressing's row paint
const LANE_STRIPE_Z := 9.7                 # candy line just inboard of the edge
const LANE_STRIPE_W := 0.34
const SEG_LEN := 24.0                      # one colour block of painted stripe
const GATE_XS: Array[float] = [300.0, 780.0]     # both ends of the strip
const GATE_BARS := 4                       # candy bars across the road at a gate
const GATE_BAR_STEP := 1.7
const GATE_BAR := Vector3(0.55, 0.02, 21.0)
const TEXT_INSET := 9.0                    # road lettering, inboard of the gate
const TEXT_WIDTH := 11.0                   # word length across one 11 m half-road
const TEXT_COLOR := Color(0.86, 0.36, 0.72)
const NEON_Y := 0.125                      # kerb face is 0..0.2: sit the line high
const NEON_SIZE := Vector3(1.0, 0.09, 0.05)      # x scaled per run
# 1.35 still clears the 1.05 HDR bloom threshold, so it glows after dark; at
# 2.1 it was the brightest object in the frame at NOON, which is not discreet.
const NEON_ENERGY := 1.35
const NEON_COLOR := Color(1.0, 0.30, 0.86)
const BLOCK_X0 := 292.0                    # first downtown block face past x=300
const BLOCK_LEN := 60.0                    # block slab edge
const BLOCK_PITCH := 86.0                  # block + street
const BLOCK_COUNT := 6                     # blocks the strip runs past
const BOLLARD_ZS: Array[float] = [462.4, 491.6]  # on the kerb slab, off roadway
const BOLLARD_TOP := 0.2                   # block slabs top out at y=0.2
const BOLLARD_SIZE := Vector3(0.24, 1.05, 0.24)
const BOLLARD_COLLAR := Vector3(0.30, 0.11, 0.30)
const BOLLARD_COLOR := Color(0.13, 0.12, 0.14)
const CANDY: Array[Color] = [
	Color(0.88, 0.16, 0.80), Color(0.62, 0.24, 0.94),
	Color(0.16, 0.85, 0.78), Color(1.0, 0.45, 0.70)]
const STATUS_COLOR := Color(1.0, 0.55, 0.92)

# ============================== STATE ========================================
var session_respect_earned := 0            # public: respect banked this session
var main_ref: Node = null
var _in_band := false
var _seen_strip := false                   # first entry gets the big flash
var _ticks := 0                            # consecutive ticks this run (combo)
var _progress := 0.0                       # seconds toward the next tick
var _still_time := 0.0                     # continuous seconds below MOVE_MIN
var _paused := false                       # AFK guard tripped
var _over_speed := false                   # edge-detect for the break flash
var _fade_left := 0.0
var _ui: CanvasLayer = null
var _status: Label = null
var _flash_label: Label = null
var _flash_left := 0.0
var _disp := Vector3i(-1, -1, -1)          # cached (combo, next, secs) text key
var _disp_paused := false


func setup(main: Node) -> void:
	main_ref = main
	if main_ref.get("smoke_mode") == true:
		set_physics_process(false)
		set_process(false)
		return
	_build_markers()
	_build_ui()


func _physics_process(delta: float) -> void:
	if main_ref == null: return
	var veh := _player()
	var inside := false
	var speed := 0.0
	if veh != null:
		var pos := veh.global_position
		speed = veh.linear_velocity.length()
		inside = pos.x >= BAND_X.x and pos.x <= BAND_X.y \
			and pos.z >= BAND_Z.x and pos.z <= BAND_Z.y and pos.y < BAND_MAX_Y
	if inside and not _in_band: _enter_band()
	elif _in_band and not inside: _leave_band()
	if not _in_band: return
	if speed > BREAK_SPEED:
		if not _over_speed: _break_combo()
		_over_speed = true
		return
	_over_speed = false
	if speed < MOVE_MIN:
		_still_time += delta
		if _still_time > STILL_GRACE and not _paused:
			_paused = true; _progress = 0.0  # AFK: void the window, keep combo
		return
	_still_time = 0.0; _paused = false
	if speed >= CRUISE_SPEED.x and speed <= CRUISE_SPEED.y:
		_progress += delta
		if _progress >= TICK_SECONDS:
			_progress -= TICK_SECONDS
			_pay_tick(veh)
	elif speed > CRUISE_SPEED.y:
		_progress = 0.0         # sped out of the roll: current 5 s window voided
	# 2..3 m/s: rolling but sub-window — progress holds, nothing accrues.


func _process(delta: float) -> void:
	_update_ui(delta)


# ============================== CRUISE RUN ===================================
func _enter_band() -> void:
	_in_band = true
	_reset_run(); _fade_left = 0.0; _disp = Vector3i(-1, -1, -1)
	if _seen_strip:
		_flash("THE CANDYLAND STRIP", 22, FLASH_SECONDS)
	else:
		_seen_strip = true
		_flash("THE CANDYLAND STRIP", 34, FLASH_BIG_SECONDS)


func _leave_band() -> void:            # quiet end — no message, status fades
	_in_band = false
	_reset_run(); _fade_left = FADE_SECONDS


func _reset_run() -> void:
	_ticks = 0; _progress = 0.0; _still_time = 0.0
	_paused = false; _over_speed = false


func _break_combo() -> void:
	_ticks = 0; _progress = 0.0
	_flash("TOO FAST FOR THE STRIP", 22, FLASH_SECONDS)


func _pay_tick(veh: RigidBody3D) -> void:
	var amount := _next_amount(veh)
	_ticks += 1
	session_respect_earned += amount
	var rb := _peer("repo_board")
	if rb != null and rb.has_method("add_respect"):
		rb.call("add_respect", amount, "CANDYLAND")
	strip_tick.emit(amount)


func _base_tick() -> int:              # 1,1,1,1,2,2,2,2,3... capped
	return mini(1 + floori(float(_ticks) / float(TICKS_PER_STEP)), TICK_CAP)


func _next_amount(veh: RigidBody3D) -> int:
	var amount := _base_tick()
	if veh != null and str(veh.get("display_name")) == SLAB_NAME:
		amount *= 2                    # driving the Candyland Slab itself
	if _is_night():
		amount *= 2                    # slabs come out at night
	return amount


func _is_night() -> bool:
	var sw := _peer("sky_weather")
	return sw != null and sw.get("is_night") == true


func _player() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	return v if (v is RigidBody3D and is_instance_valid(v)) else null


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null


# ============================== THE STRIP'S LOOK =============================
## Four layers, all of them street: painted candy lane lines the length of the
## band, a painted gate (bars + road lettering) at each end, a neon line at
## kerb height that carries the whole read at night, and knee-high candy
## bollards where the pillars used to stand.
##
## Everything is a bare MultiMeshInstance3D or Label3D — ZERO colliders, so
## nothing here can touch physics, traffic, or the smoke corridor (x >= 300),
## and zero RNG draws, so no seeded stream shifts. Repeated elements are
## MultiMeshes; the two road words are the only per-node cost.
func _build_markers() -> void:
	_paint_layer()
	_kerb_neon()
	_gate_bollards()
	_road_lettering()


## Candy edge lines down both sides of the band, in SEG_LEN colour blocks so
## the strip reads as a deliberate paint job rather than one long stripe, plus
## a bar gate laid across the roadway at each end.
func _paint_layer() -> void:
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var i := 0
	for s: float in [-1.0, 1.0]:
		var x := BAND_X.x
		while x < BAND_X.y:
			var seg := minf(SEG_LEN, BAND_X.y - x)
			xf.append(Transform3D(
				Basis.from_scale(Vector3(seg, 0.02, LANE_STRIPE_W)),
				Vector3(x + seg * 0.5, PAINT_Y, ROAD_Z + s * LANE_STRIPE_Z)))
			col.append(CANDY[i % CANDY.size()])
			i += 1
			x += seg
	var mid := (BAND_X.x + BAND_X.y) * 0.5
	for gx: float in GATE_XS:
		var inward := 1.0 if gx < mid else -1.0     # bars step INTO the band
		for b in GATE_BARS:
			xf.append(Transform3D(Basis.from_scale(GATE_BAR),
				Vector3(gx + inward * GATE_BAR_STEP * float(b), PAINT_Y, ROAD_Z)))
			col.append(CANDY[b % CANDY.size()])
	_mm(xf, col, _paint_material(), "CandylandPaint")


## A continuous lit line along the kerb face, broken only where the cross
## streets break the block. This is the night identity of the strip: at 9 cm
## tall it cannot dominate a frame, and it is the only emissive thing left.
func _kerb_neon() -> void:
	var xf: Array[Transform3D] = []
	for k in BLOCK_COUNT:
		var x0 := maxf(BAND_X.x, BLOCK_X0 + BLOCK_PITCH * float(k))
		var x1 := minf(BAND_X.y, BLOCK_X0 + BLOCK_PITCH * float(k) + BLOCK_LEN)
		if x1 - x0 < 1.0:
			continue
		for z: float in KERB_Z:
			var out := 0.03 if z < ROAD_Z else -0.03   # proud of the kerb face
			xf.append(Transform3D(
				Basis.from_scale(Vector3(x1 - x0, NEON_SIZE.y, NEON_SIZE.z)),
				Vector3((x0 + x1) * 0.5, NEON_Y, z + out)))
	_mm(xf, [], _glow_material(NEON_COLOR, NEON_ENERGY), "CandylandKerbNeon")


## Knee-high candy bollards on the kerb slab at each gate corner — exactly
## where the 14 m pillars used to stand, at 7.5 % of their height.
func _gate_bollards() -> void:
	var posts: Array[Transform3D] = []
	var collars: Array[Transform3D] = []
	for x: float in GATE_XS:
		for z: float in BOLLARD_ZS:
			posts.append(Transform3D(Basis.from_scale(BOLLARD_SIZE),
				Vector3(x, BOLLARD_TOP + BOLLARD_SIZE.y * 0.5, z)))
			collars.append(Transform3D(Basis.from_scale(BOLLARD_COLLAR),
				Vector3(x, BOLLARD_TOP + BOLLARD_SIZE.y - 0.17, z)))
	_mm(posts, [], _flat_material(BOLLARD_COLOR), "CandylandBollards")
	_mm(collars, [], _glow_material(CANDY[0], 1.3), "CandylandBollardCollars")


## The strip's name, painted on the asphalt at both gates and oriented for the
## driver arriving through that gate: letters run across the lane with their
## tops pointing the way you are travelling, the way real road copy is laid.
func _road_lettering() -> void:
	var mid := (BAND_X.x + BAND_X.y) * 0.5
	for gi in GATE_XS.size():
		var gx: float = GATE_XS[gi]
		var east := gx < mid                     # west gate: traffic enters +X
		var fwd := Vector3(1, 0, 0) if east else Vector3(-1, 0, 0)
		var right := Vector3(0, 0, 1) if east else Vector3(0, 0, -1)
		# M22 FIT: the 0.66 law assumed nine average characters, but CANDYLAND
		# advances 0.6800 em/char — the legend drew 11.33 m across an 11.0 m
		# half-road and its outer letters lay in the opposing lane. Measured
		# now. Road copy is read at a glancing angle from a moving car, so it
		# stays BIG — ~1.9 m letters, the size a real STOP legend is painted —
		# and HANDPAINT gives it the slight lean of thermoplastic laid by hand.
		var lbl := SIGN.make("CANDYLAND\nSTRIP", SIGN.HANDPAINT, TEXT_COLOR,
			TEXT_WIDTH, 0.0, 400)
		# Deliberately muted: at full brightness it read as a lightbox sunk in
		# the tarmac; shaded, it went pure black at 21:48.
		lbl.outline_modulate = Color(0.06, 0.02, 0.06, 0.8)
		lbl.transform = Transform3D(Basis(right, fwd, Vector3(0, 1, 0)),
			Vector3(gx + fwd.x * TEXT_INSET, PAINT_Y + 0.01,
				ROAD_Z + right.z * (ROAD_HALF * 0.5)))
		add_child(lbl)


# ============================== BUILD HELPERS ================================
func _mm(xforms: Array[Transform3D], cols: Array[Color],
		mat: StandardMaterial3D, mm_name: String) -> void:
	if xforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Road paint: SHADED on purpose. Paint is paint — it takes the sun by day and
## goes down with the street at night; the kerb neon is what carries the strip
## after dark. (Unshaded candy read as glow-in-the-dark tarmac at 21:48 and was
## the brightest thing on the ground in `sky_night`.) Per-instance colour so one
## draw call carries the whole four-colour palette.
func _paint_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = 0.65
	m.vertex_color_use_as_albedo = true
	return m


func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# ============================== UI ===========================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 6                      # above repo panel (5), below race (8)
	add_child(_ui)
	_status = _label(15, STATUS_COLOR)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_status.offset_left = -300.0; _status.offset_right = -14.0
	_status.offset_top = -122.0; _status.offset_bottom = -98.0  # above repo panel
	_status.modulate.a = 0.0
	_ui.add_child(_status)
	_flash_label = _label(22, Color(1.0, 0.45, 0.9))
	_flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_flash_label.offset_left = -420.0; _flash_label.offset_right = 420.0
	_flash_label.offset_top = -310.0   # clear of mission (-240..-190) slot
	_flash_label.offset_bottom = -255.0
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.modulate.a = 0.0
	_ui.add_child(_flash_label)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _flash(text: String, size: int, seconds: float) -> void:
	if _flash_label == null: return
	_flash_label.text = text
	_flash_label.add_theme_font_size_override("font_size", size)
	_flash_left = seconds


func _update_ui(delta: float) -> void:
	if _ui == null: return
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_flash_label.modulate.a = clampf(_flash_left, 0.0, 1.0)
	if _in_band:
		_status.modulate.a = 1.0
		if _paused:
			if not _disp_paused:       # rebuild text only on state change
				_disp_paused = true
				_status.text = "CANDYLAND  PAUSED — ROLL ON"
			return
		var d := Vector3i(_base_tick(), _next_amount(_player()),
			int(ceilf(TICK_SECONDS - _progress)))
		if _disp_paused or d != _disp:
			_disp_paused = false
			_disp = d
			_status.text = "CANDYLAND  combo x%d  next +%d in %ds" % [d.x, d.y, d.z]
	elif _fade_left > 0.0:
		_fade_left = maxf(0.0, _fade_left - delta)
		_status.modulate.a = _fade_left / FADE_SECONDS
