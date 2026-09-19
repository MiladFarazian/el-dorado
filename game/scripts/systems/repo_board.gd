extends Node
## REPO BOARD — EL DORADO GRANDE's first gameplay loop.
## Spawns derelict "junkers" across downtown parking lots + the frontage road,
## marks one at a time as the repo TARGET (emissive pulse + marker beam); pays
## out when the player tow-hooks the target and releases it on the impound pad.
## Hooking a non-target junker is gray work: police heat +1 per hook event.
## Peers (tow_hook, police) optional — null-checked, headless-safe, seeded RNG.

signal money_changed(total: int)
signal respect_changed(total: int)

# ============================== TUNABLES =====================================
const RNG_SEED := 4242                          # every repo-board random draw
const JUNKER_COUNT := 9
const JUNKER_MASS := Vector2(800.0, 1100.0)     # min..max (kg)
const JUNKER_SIZE := Vector3(2.0, 1.1, 4.5)     # collider + body mesh (m)
# Low sliding friction is the fiction of wheels the box doesn't physically
# have: at 0.8 the wrecker's whole traction budget went to dragging dead
# weight (4.6m in 8s of full throttle, review-verified); 0.2 tows properly.
const JUNKER_FRICTION := 0.2
const PAYOUT := Vector2i(250, 450)              # min..max ($ per repo)
const PAD_CENTER := Vector3(709.0, 0.0, 558.0)  # SE street-bed margin, flat y=0
const PAD_HALF := Vector2(7.0, 5.0)             # 14 x 10 m pad
# Target beacon (D-015 / D-032). Cycle 1 cut an 80 m opaque-edged box to a 21 m
# tapered shaft. Cycle 4 fixed what that did NOT fix: the shaft was alpha-MIX
# blended, so it crushed everything behind it to 66 % and repainted it orange —
# a sheet of smoked glass, not light — and it did so at constant strength from
# 3 m to 300 m, which put its whole budget in the near field where a marker is
# useless and a veil is fatal. It is now additive (never subtracts light) and
# beacon_kit's Driver fades the COLUMN out inside 26 m and boosts it 3x by 260 m.
# The tallest beacon in the game, because the repo target is the one objective
# you look for from across downtown.
const BEAM_HEIGHT := 21.0
const BEAM_WIDTH := 2.6
# Additive now, so ALPHA is the ramp's peak and ENERGY is the intensity the
# Driver scales. 0.30 x 1.30 = 0.39 of TARGET_GLOW added at base range.
const BEAM_ALPHA := 0.30
const BEAM_ENERGY := 1.30
# 4.6 m radius (9.2 m disc): the corona now has to carry the whole close-range
# read on its own, so it must ring a 4.5 m junker with room to spare. Its alpha
# came DOWN from 0.42 in the same pass that un-buried it: additive light on
# sunlit asphalt is far louder than the old MIX blend was, and at 0.42 the
# corona simply became the new thing painting the frame (+72 R over 10,611 px
# in `showcase_cars`; still +42 at 0.18). 0.12 lights the road it lies on and
# still leaves the 11 m read at 2.2x the findability floor.
const BEAM_RING := 4.6
const BEAM_RING_ALPHA := 0.12
const FLASH_SECONDS := 3.0
const FALL_RESET_Y := -30.0        # junkers below this snap back to their slot
const CORRIDOR := Rect2(176.0, 426.0, 34.0, 148.0)  # protected spawn lane + margin
# City layout source of truth — constants read straight off the city script.
const CITY := preload("res://scripts/world/greybox_city.gd")
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const BEACON := preload("res://scripts/world/beacon_kit.gd")
# Frontage-road curb slots (x, z) on the downtown-side strip (top y ~ 0.05).
const FRONTAGE_SLOTS: Array[Vector2] = [
	Vector2(258.0, 33.0), Vector2(334.0, 33.0), Vector2(410.0, 33.0), Vector2(486.0, 33.0)]
const PALETTE: Array[Color] = [                 # drab junker paint jobs
	Color(0.45, 0.30, 0.20), Color(0.35, 0.42, 0.48), Color(0.55, 0.50, 0.38),
	Color(0.38, 0.42, 0.30), Color(0.48, 0.46, 0.44), Color(0.30, 0.26, 0.30)]
const ARROWS: Array[String] = ["↑", "↖", "←", "↙", "↓", "↘", "→", "↗"]
const HAZARD := Color(0.92, 0.45, 0.10)
const TARGET_GLOW := Color(1.0, 0.45, 0.08)

# ============================== STATE ========================================
var main_ref: Node = null
var _panel: PanelContainer = null   # M23: yields to hud_gta
var money := 0
var respect := 0   # the second meter of the two-meter economy (story canon)
var _rng := RandomNumberGenerator.new()
var _slots: Array[Dictionary] = []   # {pos: Vector3, yaw: float, y: float}
var _junkers: Array[RigidBody3D] = []
var _target: RigidBody3D = null
var _delivering := false
var _tow: Node = null
var _prev_hooked: Node = null
var _beam: Node3D = null
var _t := 0.0
var _flash_left := 0.0
var _ui: CanvasLayer = null
var _money_label: Label = null
var _respect_label: Label = null
var _job_label: Label = null
var _flash_label: Label = null

func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED
	_build_slots(); _build_impound(); _build_beam(); _spawn_fleet()
	if main_ref.get("smoke_mode") != true: _build_ui()

func _physics_process(_delta: float) -> void:
	if main_ref == null: return
	_try_bind_tow(); _evaluate_hook_state(); _validate_fleet()

func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(_target):
		var m: StandardMaterial3D = _target.get_meta("mat", null)
		if m: m.emission_energy_multiplier = 1.2 + 0.8 * sin(_t * 5.0)
		if _beam:
			# D-068: while a LONGHORN order is live the junker beam stands down —
			# one objective on screen; the junkers stay as gray work.
			var orders := _peer("repo_orders")
			_beam.visible = not (orders != null and orders.get("active") == true)
			# The beacon's origin IS the ground point it marks (D-015) — and the
			# GROUND, not y=0. Seven of the nine junker slots stand on a parking
			# lot slab whose top is y=0.2, so a beacon pinned to y=0 buried its
			# 0.062 m ground corona 138 mm UNDER the lot: on those targets the
			# corona rendered nothing at all. Measured, not guessed — a
			# differential render from 11 m away found the beacon contributing
			# ZERO pixels below the foot. It went unnoticed for four cycles
			# because the 21 m column was loud enough to hide the fact that half
			# the beacon was missing, and only surfaced once the column stopped
			# shouting. Derived from the body, so it also tracks a junker on the
			# impound pad or swinging off the tow hook, not just a parked one.
			# A resting junker's body centre is exactly half its collider above
			# whatever it is standing on, so that subtraction IS the ground.
			var p := _target.global_position
			_beam.global_position = Vector3(p.x,
				clampf(p.y - JUNKER_SIZE.y * 0.5, 0.0, 3.0), p.z)
	elif _beam: _beam.visible = false
	_update_ui(delta)

## Prefers the city's recorded lot registry (get_lot_cells — the single source
## of truth); the RNG replay below is only a fallback for city builds without
## it, and silently desyncs if the city's draw order ever changes.
func _lot_cells() -> Array[Vector2i]:
	var city: Variant = main_ref.get("city") if main_ref != null else null
	if city is Node and is_instance_valid(city) and (city as Node).has_method("get_lot_cells"):
		var got: Variant = (city as Node).call("get_lot_cells")
		if got is Array and not (got as Array).is_empty():
			var out: Array[Vector2i] = []
			for v: Variant in got:
				if v is Vector2i:
					out.append(v)
			return out
	var r := RandomNumberGenerator.new()
	r.seed = CITY.WORLD_SEED
	var lots: Array[Vector2i] = []
	for i in CITY.GRID_COLS:
		for j in CITY.GRID_ROWS:
			if Vector2i(i, j) == CITY.GIANT_CELL: continue
			if r.randf() < CITY.LOT_CHANCE:
				lots.append(Vector2i(i, j)); continue
			var count := r.randi_range(1, 4)
			r.randi_range(0, 3)
			for _k in count:  # 5 draws per tower, mirroring the city script
				r.randf_range(14.0, 24.0); r.randf_range(14.0, 24.0)
				r.randf_range(0.75, 1.1); r.randf_range(-3.0, 3.0); r.randf_range(-3.0, 3.0)
	return lots

func _build_slots() -> void:
	var pitch: float = CITY.BLOCK + CITY.STREET
	var lot_slots: Array[Dictionary] = []
	for cell in _lot_cells():
		var cx: float = CITY.GRID_WEST + CITY.BLOCK * 0.5 + cell.x * pitch
		var cz: float = CITY.GRID_NORTH + CITY.BLOCK * 0.5 + cell.y * pitch
		for k in 4:  # two sloppy parking rows per lot, well inside the 60 m slab
			var pos := Vector3(cx + [-16.0, -6.0, 6.0, 16.0][k] + _rng.randf_range(-1.5, 1.5),
				0.0, cz + (-9.0 if k % 2 == 0 else 9.0) + _rng.randf_range(-1.5, 1.5))
			var yaw := _rng.randf_range(-0.35, 0.35) + (0.0 if _rng.randf() < 0.5 else PI)
			if not CORRIDOR.has_point(Vector2(pos.x, pos.z)):
				lot_slots.append({"pos": pos, "yaw": yaw, "y": 0.2})
	for i in range(lot_slots.size() - 1, 0, -1):  # seeded Fisher-Yates shuffle
		var j := _rng.randi_range(0, i)
		var tmp: Dictionary = lot_slots[i]; lot_slots[i] = lot_slots[j]; lot_slots[j] = tmp
	var want_lot := mini(JUNKER_COUNT - 2, lot_slots.size())
	for i in want_lot: _slots.append(lot_slots[i])
	for f in FRONTAGE_SLOTS:  # curb-parked strays along the frontage road
		if _slots.size() >= JUNKER_COUNT: break
		var pos := Vector3(f.x + _rng.randf_range(-2.0, 2.0), 0.0, f.y)
		if not CORRIDOR.has_point(Vector2(pos.x, pos.z)):
			_slots.append({"pos": pos, "yaw": PI * 0.5 + _rng.randf_range(-0.2, 0.2), "y": 0.05})
	var idx := want_lot
	while _slots.size() < JUNKER_COUNT and idx < lot_slots.size():
		_slots.append(lot_slots[idx]); idx += 1

func _spawn_fleet() -> void:
	for j in _junkers:
		if is_instance_valid(j): j.queue_free()
	_junkers.clear(); _target = null; _delivering = false
	for i in mini(JUNKER_COUNT, _slots.size()): _junkers.append(_spawn_junker(i))
	_pick_next_target()

func _spawn_junker(idx: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Junker%d" % idx
	body.mass = _rng.randf_range(JUNKER_MASS.x, JUNKER_MASS.y)
	var pm := PhysicsMaterial.new()
	pm.friction = JUNKER_FRICTION; body.physics_material_override = pm
	body.add_to_group("junker"); body.add_to_group("towable"); body.set_meta("slot", idx)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = JUNKER_SIZE; col.shape = shape; body.add_child(col)
	# SAME two rng draws as always (paint pick + darken) — the repo board's
	# seeded stream is frozen; the M9 junker style is deterministic per slot.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE[_rng.randi_range(0, PALETTE.size() - 1)].darkened(_rng.randf_range(0.0, 0.25))
	mat.roughness = 0.9; body.set_meta("mat", mat)
	var vis := Node3D.new(); body.add_child(vis)
	BODY_BUILDER.build(vis, "junker", JUNKER_SIZE, mat.albedo_color)
	# The junker style's target glow needs THIS body's material on a panel:
	# re-skin the biggest child mesh with the tracked material so the repo
	# beacon pulse (emission on "mat") still reads on the wreck.
	for c2 in vis.get_children():
		if c2 is Node3D:
			for mi2 in (c2 as Node3D).get_children():
				if mi2 is MeshInstance3D:
					(mi2 as MeshInstance3D).material_override = mat
					break
			break
	var wmesh := CylinderMesh.new()
	wmesh.top_radius = 0.32; wmesh.bottom_radius = 0.32; wmesh.height = 0.24
	var wmat := StandardMaterial3D.new(); wmat.albedo_color = Color(0.10, 0.10, 0.11)
	# Three wheels and a bare rotor — the left-front is long gone.
	for c: Vector2 in [Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new()
		w.mesh = wmesh; w.material_override = wmat; w.rotation_degrees = Vector3(0, 0, 90)
		# M19: track was wider than the body (tyres ~226 mm proud of the flank).
		# Hub at r - 0.67 = -0.35 so the tyre bottom sits ON the pavement (was
		# -0.43 = 80 mm buried). Must stay equal to vehicle_body_builder's JUNKER_W.y.
		w.position = Vector3(c.x * (JUNKER_SIZE.x * 0.5 - 0.075), -0.35, c.y * 1.45)
		body.add_child(w)
	var rotor := MeshInstance3D.new()
	var rmesh := CylinderMesh.new()
	rmesh.top_radius = 0.17; rmesh.bottom_radius = 0.17; rmesh.height = 0.1
	rotor.mesh = rmesh
	var rmat := StandardMaterial3D.new(); rmat.albedo_color = Color(0.45, 0.32, 0.2)
	rotor.material_override = rmat; rotor.rotation_degrees = Vector3(0, 0, 90)
	rotor.position = Vector3(-(JUNKER_SIZE.x * 0.5 - 0.075), -0.35, -1.45)
	body.add_child(rotor)
	add_child(body)
	body.global_transform = _slot_transform(idx)
	return body

func _slot_transform(idx: int) -> Transform3D:
	var s: Dictionary = _slots[clampi(idx, 0, _slots.size() - 1)]
	return Transform3D(Basis(Vector3.UP, s["yaw"]), Vector3(s["pos"].x, s["y"] + JUNKER_SIZE.y * 0.5 + 0.12, s["pos"].z))

func _pick_next_target() -> void:
	_clear_target_fx(); _target = null; _delivering = false
	var alive: Array[RigidBody3D] = []
	for j in _junkers:
		if is_instance_valid(j): alive.append(j)
	if alive.is_empty(): return
	_target = alive[_rng.randi_range(0, alive.size() - 1)]
	var m: StandardMaterial3D = _target.get_meta("mat", null)
	if m: m.emission_enabled = true; m.emission = TARGET_GLOW
	if _hooked_body() == _target: _delivering = true  # already holding new target

func _clear_target_fx() -> void:
	if not is_instance_valid(_target): return
	var m: StandardMaterial3D = _target.get_meta("mat", null)
	if m: m.emission_enabled = false; m.emission_energy_multiplier = 1.0

func _validate_fleet() -> void:
	for i in range(_junkers.size() - 1, -1, -1):
		var j := _junkers[i]
		if not is_instance_valid(j): _junkers.remove_at(i); continue
		if j.global_position.y < FALL_RESET_Y:  # fell out of world: re-park it
			j.global_transform = _slot_transform(j.get_meta("slot", 0))
			j.linear_velocity = Vector3.ZERO; j.angular_velocity = Vector3.ZERO
	if not is_instance_valid(_target) and not _junkers.is_empty():
		_pick_next_target()
	elif _junkers.is_empty() and not _slots.is_empty():
		_flash("NEW REPO CONTRACT"); _spawn_fleet()

func _try_bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow): return
	_tow = _peer("tow_hook")
	if _tow == null: return
	for sig: String in ["hooked", "released"]:
		if _tow.has_signal(sig) and not _tow.is_connected(sig, _on_tow_event): _tow.connect(sig, _on_tow_event)

func _on_tow_event(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_evaluate_hook_state()  # signals just force an immediate transition check

func _hooked_body() -> Node:
	if _tow == null or not is_instance_valid(_tow): return null
	var v: Variant = _tow.get("hooked_body")
	return v if (v is Node and is_instance_valid(v)) else null

func _evaluate_hook_state() -> void:
	var cur := _hooked_body()
	if cur == _prev_hooked: return
	var prev := _prev_hooked; _prev_hooked = cur
	if prev != null: _handle_release(prev)
	if cur != null: _handle_hook(cur)

func _handle_hook(body: Node) -> void:
	if body == _target:
		_delivering = true
	elif is_instance_valid(body) and body.is_in_group("junker"):
		var pol := _peer("police")  # gray work: wrong junker draws heat
		if pol != null and pol.has_method("add_heat"): pol.call("add_heat", 1, "HOOKED THE WRONG CAR")

func _handle_release(body: Node) -> void:
	if body != _target: return
	_delivering = false
	if not (body is Node3D) or not is_instance_valid(body): return
	var p := (body as Node3D).global_position
	if absf(p.x - PAD_CENTER.x) <= PAD_HALF.x and absf(p.z - PAD_CENTER.z) <= PAD_HALF.y and p.y < 4.0:
		_deliver(body)

## Public wallet API — race events, missions, and future systems pay through
## here so there is exactly one money counter in the game.
func add_money(amount: int, reason: String = "") -> void:
	money += amount
	money_changed.emit(money)
	if reason != "":
		_flash("%s %s$%s" % [reason, "+" if amount >= 0 else "-", _thousands(absi(amount))])


## Community standing — earned on the strip and in the neighborhoods, lost by
## harming them. Systems pay through here (slab_cruise, pedestrians).
func add_respect(amount: int, reason: String = "") -> void:
	respect += amount
	respect_changed.emit(respect)
	if reason != "":
		_flash("%s  RESPECT %+d" % [reason, amount])


## Public banner API — this panel owns the one flash line on screen, so systems
## with something to announce that ISN'T money (carjack: "GRAND THEFT AUTO")
## come through here instead of standing up a second competing label.
func flash(text: String) -> void:
	_flash(text)


func _deliver(body: Node) -> void:
	var pay := _rng.randi_range(PAYOUT.x, PAYOUT.y)
	money += pay; money_changed.emit(money)
	_junkers.erase(body); _clear_target_fx(); _target = null
	body.queue_free()
	if _junkers.is_empty():
		_flash("REPO PAID $%d — NEW REPO CONTRACT" % pay); _spawn_fleet()
	else:
		_flash("REPO PAID $%d" % pay); _pick_next_target()

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = sys.get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null

## D-058 (Milad, 2026-09-13: "the drop-off area was blocking the vehicle"): the
## pad WAS a 24 cm slab with 22 cm lips, all StaticBody3D — a curb. The wrecker
## climbs it on its wheels; a towed junker or the Brisket is a BOX on a chain and
## a box cannot climb a step, so the delivery stopped dead against the edge
## (probe stage 7: z -7.2 m from centre, exactly the slab face). The pad is now
## PAINT: 1.5 cm of grey and the hazard stripes as visuals with NO collider.
## Delivery was always a position test (_handle_release), never a contact.
func _build_impound() -> void:
	_paint_box(Vector3(PAD_HALF.x * 2.0, 0.015, PAD_HALF.y * 2.0), PAD_CENTER + Vector3(0, 0.0075, 0), Color(0.30, 0.30, 0.32), false)
	for s: float in [-1.0, 1.0]:  # hazard-orange border stripes, flush
		_paint_box(Vector3(PAD_HALF.x * 2.0, 0.012, 0.8), PAD_CENTER + Vector3(0, 0.02, s * (PAD_HALF.y - 0.4)), HAZARD, true)
		_paint_box(Vector3(0.8, 0.012, PAD_HALF.y * 2.0 - 1.6), PAD_CENTER + Vector3(s * (PAD_HALF.x - 0.4), 0.02, 0), HAZARD, true)
	# Sign pole + hazard board just east of the pad.
	_static_box(Vector3(0.25, 4.2, 0.25), PAD_CENTER + Vector3(9.0, 2.1, 0), Color(0.5, 0.5, 0.5), false)
	_static_box(Vector3(2.6, 1.3, 0.2), PAD_CENTER + Vector3(9.0, 3.9, 0), HAZARD, true)

## Visual only: the pad and its stripes must never be a curb to a towed box.
func _paint_box(size: Vector3, pos: Vector3, color: Color, emissive: bool) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 0.85
	if emissive: m.emission_enabled = true; m.emission = color
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m
	mi.position = pos
	add_child(mi)

func _static_box(size: Vector3, pos: Vector3, color: Color, emissive: bool) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = size; col.shape = shape; body.add_child(col)
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 0.85
	if emissive: m.emission_enabled = true; m.emission = color
	var bm := BoxMesh.new(); bm.size = size
	var mi := MeshInstance3D.new(); mi.mesh = bm; mi.material_override = m; body.add_child(mi)
	body.position = pos
	add_child(body)

func _build_beam() -> void:
	_beam = BEACON.beacon(TARGET_GLOW, BEAM_HEIGHT, BEAM_WIDTH,
		BEAM_ALPHA, BEAM_ENERGY, BEAM_RING, BEAM_RING_ALPHA)
	_beam.visible = false
	add_child(_beam)

func _build_ui() -> void:
	_ui = CanvasLayer.new(); _ui.layer = 5
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -300.0; panel.offset_top = -90.0; panel.offset_right = -14.0; panel.offset_bottom = -14.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_ui.add_child(panel)
	_panel = panel  # M23: hidden while hud_gta draws cash + objective itself
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	_money_label = _label(24, Color(0.65, 0.95, 0.55))
	vbox.add_child(_money_label)
	_respect_label = _label(13, Color(0.95, 0.75, 0.35))
	vbox.add_child(_respect_label)
	_job_label = _label(15, Color(0.9, 0.9, 0.9))
	vbox.add_child(_job_label)
	_flash_label = _label(30, Color(1.0, 0.72, 0.2))
	_flash_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_flash_label.offset_left = -320.0; _flash_label.offset_right = 320.0
	_flash_label.offset_top = -170.0; _flash_label.offset_bottom = -120.0; _flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.modulate.a = 0.0
	_ui.add_child(_flash_label)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", color)
	return l

func _flash(text: String) -> void:
	if _flash_label == null: return
	_flash_label.text = text; _flash_left = FLASH_SECONDS

func _update_ui(delta: float) -> void:
	if _ui == null: return
	if _panel != null:
		var sys: Variant = main_ref.get("systems") if main_ref != null else null
		_panel.visible = not (sys is Dictionary and (sys as Dictionary).has("hud_gta"))
	_money_label.text = "$%d" % money
	if _respect_label != null:
		_respect_label.text = "RESPECT %d" % respect
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_flash_label.modulate.a = clampf(_flash_left, 0.0, 1.0)
	var line := "REPO: scanning..."
	if is_instance_valid(_target):
		if _delivering:
			var d := Vector2(_target.global_position.x - PAD_CENTER.x, _target.global_position.z - PAD_CENTER.z).length()
			line = "DELIVER TO IMPOUND: %dm" % int(d)
		else:
			var veh: Variant = main_ref.get("vehicle") if main_ref else null
			if veh is Node3D and is_instance_valid(veh):
				var dir: Vector3 = _target.global_position - (veh as Node3D).global_position
				dir.y = 0.0
				line = "REPO: %s %dm" % [_arrow(veh, dir), int(dir.length())]
	_job_label.text = line

func _arrow(veh: Node3D, dir: Vector3) -> String:
	var fwd: Vector3 = -veh.global_transform.basis.z
	fwd.y = 0.0
	# `x < 0.001` is FALSE for NaN, so a length test alone let a non-finite
	# basis through to normalize() and spammed the log with "Vector3 cannot be
	# normalized". A HUD that renders a direction it does not have is a HUD that
	# lies; print the neutral glyph instead.
	if not fwd.is_finite() or not dir.is_finite(): return "•"
	if fwd.length_squared() < 0.001 or dir.length_squared() < 0.001: return "•"
	return ARROWS[wrapi(int(roundf(fwd.normalized().signed_angle_to(dir.normalized(), Vector3.UP) / (PI * 0.25))), 0, 8)]


static func _thousands(n: int) -> String:
	var t := str(n)
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out
