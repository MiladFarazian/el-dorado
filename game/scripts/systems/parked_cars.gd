extends Node
## PARKED CARS v1 — static curbside stock for downtown Dorado.
## Traffic.gd's static sibling: frozen-kinematic RigidBody3D shells seeded once
## at boot along BOTH curbs of the seven north-south streets, ~35% of 14 m
## slots so the curb reads like a patchy weekday, never in the protected smoke
## corridor or within 15 m of a crossing. Right-hand rule facing: the east
## curb's traffic drives -Z so its cars nose -Z; the west curb noses +Z.
## Carjack sees them as EMPTY rides ("carjack_has_driver" = false — free steal,
## nobody tossed, no stars); the tow hook takes one with NO heat (empty car,
## gray-area repo work); any dynamic contact unfreezes one PERMANENTLY into
## loose towable debris. Stock never respawns — downtown empties out as the
## player works it. DISABLED in smoke mode.

# ============================== TUNABLES =====================================
const RNG_SEED := 4141; const FLEET_CAP := 44  # seed; hard stock ceiling
# Streets per scripts/world/greybox_city.gd: N-S centrelines x = 193 + 86*i
# (i 0..6); E-W crossings z = 133 + 86*j (j 0..4). Same grid traffic drives.
const STREET_X0 := 193.0; const STREET_DX := 86.0; const STREET_COUNT := 7
const CROSS_Z0 := 133.0; const CROSS_DZ := 86.0; const CROSS_COUNT := 5
const CURB_X := 8.6                  # curb lane = centreline ± this (m)
const SLOT_SPAN := Vector2(60.0, 540.0); const SLOT_STEP := 14.0  # usable z; pitch
const FILL_CHANCE := 0.35            # patchy weekday curb, not a car lot
const INTERSECT_CLEAR := 15.0        # no parking this close to a crossing (m)
# Protected corridor (traffic.gd's rect): street x=193's curbs both fall in
# the x band, so that street loses its ENTIRE z 424..576 stretch.
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)
const JITTER_ALONG := 0.6; const JITTER_ACROSS := 0.15  # nobody parks straight (m)
const JITTER_YAW := 0.05             # ...or square to the curb (rad)
const SEDAN_SIZE := Vector3(1.9, 1.05, 4.4); const SEDAN_RIDE := 0.85
const TRUCK_SIZE := Vector3(2.15, 1.3, 5.2); const TRUCK_RIDE := 1.1  # lifted
const SEDAN_WHEEL := 0.32; const TRUCK_WHEEL := 0.44
const CAR_MASS := 1300.0; const TRUCK_MASS := 1750.0
const CAR_FRICTION := 0.3; const TRUCK_CHANCE := 0.18
const PALETTE: Array[Color] = [      # traffic's civilian whites/silvers...
	Color(0.93, 0.93, 0.9), Color(0.87, 0.87, 0.85), Color(0.76, 0.77, 0.79),
	Color(0.64, 0.66, 0.69), Color(0.55, 0.57, 0.59),
	# ...cut with suburban daily-driver paint: dusty red, sage, navy, tan.
	Color(0.55, 0.22, 0.18), Color(0.55, 0.6, 0.5),
	Color(0.2, 0.26, 0.38), Color(0.66, 0.58, 0.44)]
# What a jacked shell turns into (carjack.gd reads the "jack_profile" meta).
const SEDAN_PROFILE := "res://data/vehicles/sedan.json"
const TRUCK_PROFILE := "res://data/vehicles/brisket.json"
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")

# ============================== STATE ========================================
var main_ref: Node = null; var _tow: Node = null
var _rng := RandomNumberGenerator.new()
var _cars: Array[Dictionary] = []    # {body, frozen}
var _spawned := 0
var _sedan_wheel: CylinderMesh; var _truck_wheel: CylinderMesh
var _wheel_mat: StandardMaterial3D; var _phys_mat: PhysicsMaterial

func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return  # smoke gate: spawn NOTHING
	_build_shared(); _fill_curbs()

## One wheel mesh/material set shared by the whole curb; body paint and detail
## materials are cached inside vehicle_body_builder, keyed by color.
func _build_shared() -> void:
	_sedan_wheel = CylinderMesh.new(); _sedan_wheel.height = 0.24
	_sedan_wheel.top_radius = SEDAN_WHEEL; _sedan_wheel.bottom_radius = SEDAN_WHEEL
	_truck_wheel = CylinderMesh.new(); _truck_wheel.height = 0.32
	_truck_wheel.top_radius = TRUCK_WHEEL; _truck_wheel.bottom_radius = TRUCK_WHEEL
	_wheel_mat = StandardMaterial3D.new(); _wheel_mat.albedo_color = Color(0.1, 0.1, 0.11)
	_phys_mat = PhysicsMaterial.new(); _phys_mat.friction = CAR_FRICTION

# ============================== PLACEMENT ====================================
## All at boot, all seeded. Slots are enumerated in one canonical order
## (street, curb, z), then Fisher-Yates shuffled with the same rng BEFORE the
## 35% fill roll: the 44-car cap binds long before the slot list runs out
## (~336 eligible slots), and a shuffled walk spreads the stock across the
## whole downtown instead of jamming every car onto the westernmost streets.
## Same seed -> same shuffle -> same fleet, byte for byte.
func _fill_curbs() -> void:
	var slots := _build_slots()
	for i in range(slots.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := slots[i]; slots[i] = slots[j]; slots[j] = t
	for slot: Vector3 in slots:
		if _cars.size() >= FLEET_CAP: break
		if _rng.randf() < FILL_CHANCE: _park(slot)

## Slot = Vector3(curb x, side sign, slot z). Side +1 is the east curb of its
## street (centreline +8.6): right-hand traffic there drives -Z, so its parked
## cars nose -Z; the west curb (-1) noses +Z.
func _build_slots() -> Array[Vector3]:
	var slots: Array[Vector3] = []
	for i in STREET_COUNT:
		var cx := STREET_X0 + STREET_DX * float(i)
		for side: float in [1.0, -1.0]:
			var z := SLOT_SPAN.x
			while z <= SLOT_SPAN.y:
				if _slot_open(cx + side * CURB_X, z):
					slots.append(Vector3(cx + side * CURB_X, side, z))
				z += SLOT_STEP
	return slots

func _slot_open(x: float, z: float) -> bool:
	if CORRIDOR.has_point(Vector2(x, z)): return false  # smoke path stays sacred
	for j in CROSS_COUNT:
		if absf(z - (CROSS_Z0 + CROSS_DZ * float(j))) < INTERSECT_CLEAR: return false
	return true

func _park(slot: Vector3) -> void:
	var truck := _rng.randf() < TRUCK_CHANCE
	var size := TRUCK_SIZE if truck else SEDAN_SIZE
	var ride := TRUCK_RIDE if truck else SEDAN_RIDE  # lifted trucks sit higher
	var paint: Color = PALETTE[_rng.randi_range(0, PALETTE.size() - 1)]
	var pos := Vector3(slot.x + _rng.randf_range(-JITTER_ACROSS, JITTER_ACROSS), ride,
		slot.z + _rng.randf_range(-JITTER_ALONG, JITTER_ALONG))
	var fwd := Vector3(0.0, 0.0, -slot.y).rotated(
		Vector3.UP, _rng.randf_range(-JITTER_YAW, JITTER_YAW))
	var body := RigidBody3D.new()
	_spawned += 1; body.name = "Parked%d" % _spawned
	body.mass = TRUCK_MASS if truck else CAR_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	body.physics_material_override = _phys_mat
	# 8, not 2: speculative contacts with the road slab exhaust a budget of 2
	# and dynamic-body contacts then never report (house law, per traffic.gd).
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("civilian"); body.add_to_group("towable")
	body.set_meta("jack_profile", TRUCK_PROFILE if truck else SEDAN_PROFILE)
	# EMPTY by contract: carjack reads this meta and treats the car as free to
	# take — no ejected driver, no stars. A parked car is the easy steal.
	body.set_meta("carjack_has_driver", false)
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = size; col.shape = shape; body.add_child(col)
	var vis := Node3D.new(); body.add_child(vis)
	BODY_BUILDER.build(vis, "pickup" if truck else "sedan", size, paint)
	var radius := TRUCK_WHEEL if truck else SEDAN_WHEEL; var zoff := size.z * 0.5 - radius - 0.7
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new(); w.mesh = _truck_wheel if truck else _sedan_wheel
		w.material_override = _wheel_mat; w.rotation_degrees = Vector3(0, 0, 90)
		# M19: see traffic.gd — track was wider than the body (tyres ~235 mm proud).
		w.position = Vector3(c.x * (size.x * 0.5 - 0.075), radius - ride, c.y * zoff)
		body.add_child(w)
	# Placed BEFORE add_child — deliberately unlike traffic's per-frame _place.
	# 44 bodies boot in a single frame, and a body that enters the tree at the
	# origin (even briefly) sits coincident with its 43 siblings: the first
	# physics step reports those kinematic-kinematic contacts, _on_contact
	# unfreezes the lot, and depenetration turns the curb into shrapnel.
	# Registered already on its curb, no step ever sees an overlap.
	body.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	body.body_entered.connect(_on_contact.bind(body))
	_cars.append({"body": body, "frozen": true})

# ============================== MAINTENANCE ==================================
## Cheap roster sweep, no allocation, no rays: carjack CONVERTS a stolen shell
## (strips its collision and frees the body), so entries can vanish any frame.
## No respawns during play — parked stock depletes as it gets stolen or
## wrecked, and the curb stays honest about it.
func _physics_process(_delta: float) -> void:
	if main_ref == null: return
	_bind_tow()
	for i in range(_cars.size() - 1, -1, -1):
		var body := _cars[i]["body"] as RigidBody3D
		if not is_instance_valid(body) or not body.is_inside_tree():
			_cars.remove_at(i)

# ============================== CRASH / HOOK HANDOFF =========================
## Permanent handoff to loose physics: once bumped or hooked, a parked car is
## towable debris forever (no re-freeze, no respawn). Unlike traffic there is
## no lane speed to hand over — a parked car wakes at rest.
func _unfreeze(car: Dictionary) -> void:
	if not bool(car["frozen"]): return
	car["frozen"] = false; var body := car["body"] as RigidBody3D
	if is_instance_valid(body): body.freeze = false

## Static world is NOT a crash: the engine reports speculative contacts with
## the road slab cars float over — that would instantly unfreeze every curb.
func _on_contact(other: Node, body: Node) -> void:
	if other is StaticBody3D: return
	var car := _find(body)
	if not car.is_empty() and bool(car["frozen"]): _unfreeze(car)

## Hooked = repo'd. Unfreeze so the chain pulls a loose body, and charge NO
## heat (unlike traffic's _on_hooked): the car is empty, this is gray-area
## repo work, and there is no witness system yet to say otherwise.
func _on_hooked(body: Node) -> void:
	var car := _find(body)
	if car.is_empty() or not bool(car["frozen"]): return
	_unfreeze(car)

# ============================== PLUMBING =====================================
func _bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow): return
	_tow = _peer("tow_hook")
	if _tow != null and _tow.has_signal("hooked") and not _tow.is_connected("hooked", _on_hooked):
		_tow.connect("hooked", _on_hooked)

func _find(body: Node) -> Dictionary:
	for car in _cars:
		if car["body"] == body: return car
	return {}

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null
