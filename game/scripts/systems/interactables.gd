extends Node
## INTERACTABLES — street props that answer back. Three families:
##
##   DR. ZING machines (one per strip mall): $3 buys +25 health, because the
##   only healthcare on the frontage road is a soda with a classified flavor.
##   CATTLEMAN'S TRUST ATMs (one per mall): G doesn't withdraw, it ROBS —
##   seeded cash now, +2 stars now, a 6 s two-tone alarm, and the machine is
##   empty forever. The risk/reward loop in one dark-green box.
##   Hydrants + trash bins: city_dressing records WHERE (its frozen draw
##   stream untouched); we stand real frozen-kinematic props there. A car
##   knocks a hydrant flying and the main breaks — a 7 s water fountain.
##
## One prompt label (slot 136 px, above carjack's 96 and the tow hint's 56),
## on-foot only, nearest prop within reach. Audio is synthesized in code
## (vehicle_audio.gd style), every player stopped on teardown (4.7.1 leaks
## playing streams at quit). ENTIRELY INERT in smoke mode: no props, no UI,
## no audio buffers. Peers null-checked; dressing accessors optional.

# ============================== TUNABLES =====================================
const SIGN := preload("res://scripts/world/sign_kit.gd")
const RNG_SEED := 0x51AC             # ATM payouts (runtime draws, seeded)
const INTERACT_RANGE := 2.4          # character origin -> prop centre (m)
const SCAN_PERIOD := 0.2             # nearest-prop scan cadence (s), not per-frame
const GROUND_Y := 0.01               # at-grade corridor apron top (greybox_city)
# Protected corridor — the smoke lane. Nothing with collision goes here, ever.
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)   # x 174..212, z 424..576
const MALL_MACHINE_DX := 7.5         # vending east of mall centre, ATM west
const MALL_MACHINE_Z := 37.4         # just proud of the mall face at |z|=38

# DR. ZING — canon soda (naming bible §7): "24 flavors, one is classified".
const ZING_PRICE := 3
const ZING_HEAL := 25.0
const FULL_HEALTH := 100.0           # player_character.MAX_HEALTH (constants
                                     # aren't readable via get(), so mirrored)
const ZING_SIZE := Vector3(0.9, 1.9, 0.7)
const ZING_MAROON := Color(0.33, 0.08, 0.11)
const ZING_CREAM := Color(0.98, 0.92, 0.80)
const ZING_PROMPT := "G — DR. ZING  $3"

# CATTLEMAN'S TRUST ATM — the bank gets robbed one sidewalk box at a time.
const ATM_PAYOUT := Vector2i(180, 350)   # min..max ($, seeded draw per crack)
const ATM_HEAT := 2
const ATM_SIZE := Vector3(0.7, 1.5, 0.5)
const ATM_GREEN := Color(0.06, 0.22, 0.13)
const ATM_SCREEN := Color(0.55, 0.85, 0.60)
const ATM_PROMPT := "G — CRACK THE ATM  (+2★)"
const ATM_EMPTIED_META := "atm_emptied"  # forever — prompt shows nothing after

# Hydrants / bins — frozen kinematic until something that isn't scenery hits.
const HYDRANT_MASS := 40.0
const HYDRANT_COLLIDER := Vector3(0.30, 0.88, 0.30)
const HYDRANT_RED := Color(0.72, 0.14, 0.10)     # same red the MM version wore
const BIN_MASS := 25.0
const BIN_SIZE := Vector3(0.62, 0.95, 0.62)
const BIN_GREEN := Color(0.20, 0.32, 0.24)       # same green as the old MM
const KNOCK_CARRY := 0.8             # share of the striker's velocity inherited
const KNOCK_POP := 2.5               # up-fling so the hit reads as a launch (m/s)
const BASE_META := "interact_base"   # prop's original base point (jet origin)

# Water jet: broken main under the knocked hydrant.
const JET_AMOUNT := 120
const JET_LIFETIME := 1.1
const JET_EMIT_SECONDS := 7.0        # emit this long...
const JET_TAIL := 1.2                # ...then let the last drops land, then free
const JET_VELOCITY := Vector2(9.0, 13.0)
const JET_COLOR := Color(0.72, 0.86, 1.0, 0.85)

# Prompt UI — centre-bottom slot ABOVE carjack's prompt (96) and tow hint (56).
const PROMPT_MARGIN := 136
const PROMPT_FONT_SIZE := 21
const PROMPT_COLOR := Color(0.95, 0.92, 0.8)

# Audio — all synthesized at setup, 16-bit mono 22050 Hz (vehicle_audio style).
const MIX_RATE := 22050
const CLICK_SAMPLES := 1500          # ~0.07 s vending thunk
const CLICK_HZ := 1320.0
const CLICK_DECAY := 70.0
const CLICK_SECONDS := 0.2           # player lifetime (clip + margin)
const CLICK_DB := -6.0
const CLICK_UNIT := 6.0
const CLICK_MAX_DIST := 30.0
# Two-tone alarm: 1/6 s per tone -> the pair alternates at 3 Hz. Each segment
# holds WHOLE cycles (117 -> ~702 Hz, 158 -> ~948 Hz), so every boundary and
# the loop point land on a zero crossing — click-free.
const ALARM_SEG_SAMPLES := 3675
const ALARM_CYCLES: Array[int] = [117, 158]
const ALARM_GAIN := 0.55
const ALARM_SECONDS := 6.0
const ALARM_DB := -9.0
const ALARM_UNIT := 14.0
const ALARM_MAX_DIST := 240.0

# ============================== STATE ========================================
var main_ref: Node = null
var _rng := RandomNumberGenerator.new()
# Machines the prompt can point at: {body, pos, kind ("zing"/"atm"), dead}.
var _stations: Array[Dictionary] = []
var _near := -1                      # index into _stations, -1 = nothing close
var _scan_t := 0.0
var _hydrants := 0                   # spawn counters (unique node names)
var _bins := 0
var _ui: CanvasLayer = null
var _prompt: Label = null
var _click_stream: AudioStreamWAV = null
var _alarm_stream: AudioStreamWAV = null
var _audio: Array[Dictionary] = []   # {p: AudioStreamPlayer3D, left: float}
var _jets: Array[Dictionary] = []    # {node: GPUParticles3D, left: float}


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: no props, no UI, no audio buffers
	_rng.seed = RNG_SEED
	_click_stream = _build_click()
	_alarm_stream = _build_alarm_loop()
	_spawn_machines()
	_spawn_street_props()
	_build_ui()


## Player vehicle swaps don't touch street furniture — explicit no-op contract.
func on_vehicle_changed(_vehicle: Node) -> void:
	pass


# ============================== MACHINES =====================================
## One DR. ZING + one CATTLEMAN'S TRUST ATM per recorded strip mall, both on
## the road-facing face. Slot format (greybox_city): (mall centre x, side, 0),
## mall at z = side*44, face at z = side*38.
func _spawn_machines() -> void:
	var city := _city()
	if city == null or not city.has_method("get_mall_slots"):
		return
	var slots: Variant = city.call("get_mall_slots")
	if not (slots is Array):
		return
	for v: Variant in (slots as Array):
		if not (v is Vector3):
			continue
		var slot := v as Vector3
		var side := slot.y
		var yaw := 0.0 if side < 0.0 else PI   # face the frontage road
		_zing_machine(Vector3(slot.x + MALL_MACHINE_DX, GROUND_Y, side * MALL_MACHINE_Z), yaw)
		_atm(Vector3(slot.x - MALL_MACHINE_DX, GROUND_Y, side * MALL_MACHINE_Z), yaw)


func _zing_machine(base: Vector3, yaw: float) -> void:
	if CORRIDOR.has_point(Vector2(base.x, base.z)):
		return  # never any collision in the protected corridor
	var body := _machine_body("ZingMachine%d" % _stations.size(), base, yaw, ZING_SIZE)
	_box_mesh(body, ZING_SIZE, Vector3(0, ZING_SIZE.y * 0.5, 0), ZING_MAROON, false)
	# Emissive cream selection panel on the front face (+Z is road-facing).
	_box_mesh(body, Vector3(0.62, 0.85, 0.06), Vector3(0, 1.02, ZING_SIZE.z * 0.5 + 0.03),
		ZING_CREAM, true)
	_face_label(body, "DR. ZING", Vector3(0, 1.66, ZING_SIZE.z * 0.5 + 0.01),
		44, 0.8, ZING_CREAM)
	_stations.append({"body": body, "pos": base + Vector3(0, ZING_SIZE.y * 0.5, 0),
		"kind": "zing", "dead": false})


func _atm(base: Vector3, yaw: float) -> void:
	if CORRIDOR.has_point(Vector2(base.x, base.z)):
		return
	var body := _machine_body("TrustATM%d" % _stations.size(), base, yaw, ATM_SIZE)
	_box_mesh(body, ATM_SIZE, Vector3(0, ATM_SIZE.y * 0.5, 0), ATM_GREEN, false)
	_box_mesh(body, Vector3(0.44, 0.34, 0.06), Vector3(0, 1.02, ATM_SIZE.z * 0.5 + 0.03),
		ATM_SCREEN, true)
	_face_label(body, "CATTLEMAN'S TRUST", Vector3(0, 1.36, ATM_SIZE.z * 0.5 + 0.01),
		36, 0.64, Color(0.75, 0.95, 0.7))
	_stations.append({"body": body, "pos": base + Vector3(0, ATM_SIZE.y * 0.5, 0),
		"kind": "atm", "dead": false})


func _machine_body(prop_name: String, base: Vector3, yaw: float, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = prop_name
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(col)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	body.position = base
	body.rotation.y = yaw
	return body


# ============================== STREET PROPS =================================
## The dressing layer records hydrant/bin spots (same frozen RNG draws it always
## made); we stand physics props there. Accessors optional by contract: if the
## dressing node or its methods are missing, nothing spawns and nothing breaks.
func _spawn_street_props() -> void:
	var city := _city()
	if city == null:
		return
	var dressing := city.get_node_or_null("CityDressing")
	if dressing == null:
		return
	if dressing.has_method("get_hydrant_spots"):
		var hs: Variant = dressing.call("get_hydrant_spots")
		if hs is Array:
			for v: Variant in (hs as Array):
				if v is Vector3 and not CORRIDOR.has_point(Vector2((v as Vector3).x, (v as Vector3).z)):
					_spawn_hydrant(v as Vector3)
	if dressing.has_method("get_bin_spots"):
		var bs: Variant = dressing.call("get_bin_spots")
		if bs is Array:
			for v: Variant in (bs as Array):
				if v is Vector3 and not CORRIDOR.has_point(Vector2((v as Vector3).x, (v as Vector3).z)):
					_spawn_bin(v as Vector3)


## Frozen kinematic fire hydrant: body + cap + side nubs in the same red the
## MultiMesh version wore. First non-scenery contact unfreezes it (it flies)
## and breaks the main — a water jet at the original base.
func _spawn_hydrant(spot: Vector3) -> void:
	_hydrants += 1
	var body := _prop_body("Hydrant%d" % _hydrants, HYDRANT_MASS, HYDRANT_COLLIDER)
	_box_mesh(body, Vector3(0.26, 0.72, 0.26), Vector3(0, -0.08, 0), HYDRANT_RED, false)
	_box_mesh(body, Vector3(0.18, 0.16, 0.18), Vector3(0, 0.36, 0), HYDRANT_RED, false)
	for s: float in [-1.0, 1.0]:  # side nubs (the hose caps)
		_box_mesh(body, Vector3(0.14, 0.14, 0.14), Vector3(s * 0.19, 0.06, 0), HYDRANT_RED, false)
	body.set_meta(BASE_META, spot)
	body.set_meta("is_hydrant", true)  # M14: lets prop_shot break the main too
	body.body_entered.connect(_on_prop_hit.bind(body, true))
	# TRANSFORM BEFORE add_child — the project's oldest recurring bug (D-015,
	# and QA cycle 1 found it here). add_child first puts EVERY prop at the
	# world origin for one frame; with contact_monitor on, all 45 props resolve
	# against each other there, `_on_prop_hit` fires (its only guard is
	# StaticBody3D), and all 26 hydrants break their mains on physics frame 1.
	# The tell in the probe log: a hydrant at x=722 "hit by" TrashBin1 at x=179.
	body.transform = Transform3D(Basis.IDENTITY,
		spot + Vector3(0, HYDRANT_COLLIDER.y * 0.5, 0))
	add_child(body)


func _spawn_bin(spot: Vector3) -> void:
	_bins += 1
	var body := _prop_body("TrashBin%d" % _bins, BIN_MASS, BIN_SIZE)
	_box_mesh(body, BIN_SIZE, Vector3.ZERO, BIN_GREEN, false)
	body.set_meta(BASE_META, spot)
	body.body_entered.connect(_on_prop_hit.bind(body, false))
	# Transform BEFORE add_child — see _spawn_hydrant.
	body.transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, BIN_SIZE.y * 0.5, 0))
	add_child(body)


func _prop_body(prop_name: String, mass: float, collider: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.mass = mass
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.contact_monitor = true
	body.max_contacts_reported = 8
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collider
	col.shape = shape
	body.add_child(col)
	return body


## Something hit a frozen prop. Scenery (StaticBody) never wakes one — only
## vehicles and other movers do. The prop inherits most of the striker's
## velocity plus a pop so the launch reads; hydrants also break the main.
func _on_prop_hit(other: Node, prop: RigidBody3D, is_hydrant: bool) -> void:
	if prop == null or not is_instance_valid(prop) or not prop.freeze:
		return  # already knocked loose — physics owns it now
	if other == null or other is StaticBody3D:
		return
	prop.freeze = false
	if is_instance_valid(other) and other is RigidBody3D:
		prop.linear_velocity = (other as RigidBody3D).linear_velocity * KNOCK_CARRY \
			+ Vector3.UP * KNOCK_POP
	if is_hydrant:
		var base: Variant = prop.get_meta(BASE_META, prop.global_position)
		_start_jet(base if base is Vector3 else prop.global_position)


## PUBLIC (combat, M14): a bullet hit a frozen street prop. Same knock-loose
## as a vehicle strike minus the inherited ride (bullets shove, they don't
## carry); hydrants still break the main. Gated on BASE_META so parked cars
## and other frozen bodies never route through here.
func prop_shot(prop: RigidBody3D) -> void:
	if prop == null or not is_instance_valid(prop) or not prop.freeze:
		return
	if not prop.has_meta(BASE_META):
		return  # not one of ours
	prop.freeze = false
	prop.linear_velocity = Vector3.UP * KNOCK_POP
	if prop.get_meta("is_hydrant", false):
		var base: Variant = prop.get_meta(BASE_META, prop.global_position)
		_start_jet(base if base is Vector3 else prop.global_position)


func _start_jet(base: Vector3) -> void:
	var jet := GPUParticles3D.new()
	jet.amount = JET_AMOUNT
	jet.lifetime = JET_LIFETIME
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 7.0
	pm.initial_velocity_min = JET_VELOCITY.x
	pm.initial_velocity_max = JET_VELOCITY.y
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	jet.process_material = pm
	var drop := BoxMesh.new()
	drop.size = Vector3(0.10, 0.22, 0.10)
	var m := StandardMaterial3D.new()
	m.albedo_color = JET_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = m
	jet.draw_pass_1 = drop
	jet.emitting = true
	add_child(jet)
	jet.global_position = base + Vector3(0, 0.25, 0)
	_jets.append({"node": jet, "left": JET_EMIT_SECONDS + JET_TAIL})


# ============================== INTERACTION ==================================
func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_scan_t += delta
	if _scan_t >= SCAN_PERIOD:
		_scan_t = 0.0
		_refresh_near()
	if _near < 0:
		return
	if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		_interact()


## The 0.2 s nearest scan — never per-frame over all props (contract).
func _refresh_near() -> void:
	var ch := _character()
	if ch == null or _health(ch) <= 0.0:
		_set_near(-1)
		return
	var origin := ch.global_position
	var best := -1
	var best_d := INTERACT_RANGE
	for i in _stations.size():
		if bool(_stations[i]["dead"]):
			continue  # cracked ATM: the prompt shows nothing, forever
		var d := origin.distance_to(_stations[i]["pos"] as Vector3)
		if d < best_d:
			best_d = d
			best = i
	_set_near(best)


func _interact() -> void:
	var ch := _character()
	if ch == null or _health(ch) <= 0.0 or _near < 0 or _near >= _stations.size():
		return
	var st := _stations[_near]
	if bool(st["dead"]):
		return
	# Re-check reach against fresh positions — the scan can be 0.2 s stale.
	if ch.global_position.distance_to(st["pos"] as Vector3) > INTERACT_RANGE:
		return
	if str(st["kind"]) == "zing":
		_buy_zing(st, ch)
	else:
		_crack_atm(st)


## $3, +25 health. Full health drinks free by drinking nothing; no cash gets
## the house policy read aloud.
func _buy_zing(st: Dictionary, ch: Node3D) -> void:
	if _health(ch) >= FULL_HEALTH:
		_flash("YOU'RE FULL OF ZING.")
		return
	var repo := _peer("repo_board")
	if repo == null:
		return
	var money: Variant = repo.get("money")
	if money is int and int(money) < ZING_PRICE:
		_flash("NO CASH — DR. ZING DON'T DO CREDIT")
		return
	if repo.has_method("add_money"):
		repo.call("add_money", -ZING_PRICE, "DR. ZING")
	if ch.has_method("heal"):
		ch.call("heal", ZING_HEAL)
	_play_on(st["body"] as Node, _click_stream, CLICK_SECONDS,
		CLICK_DB, CLICK_UNIT, CLICK_MAX_DIST)


## The robbery: seeded cash now, stars now, alarm now, empty forever.
func _crack_atm(st: Dictionary) -> void:
	st["dead"] = true
	var body: Variant = st["body"]
	if body is Node and is_instance_valid(body):
		(body as Node).set_meta(ATM_EMPTIED_META, true)
	var pay := _rng.randi_range(ATM_PAYOUT.x, ATM_PAYOUT.y)
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", pay, "ATM CRACKED")
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", ATM_HEAT, "ROBBED AN ATM")
	if body is Node and is_instance_valid(body):
		_play_on(body as Node, _alarm_stream, ALARM_SECONDS,
			ALARM_DB, ALARM_UNIT, ALARM_MAX_DIST)
	_refresh_near()  # drop the prompt immediately, not a scan-tick later


# ============================== TIMED CLEANUP ================================
func _process(delta: float) -> void:
	if main_ref == null:
		return
	# Prompt gate, every frame: on foot AND alive, else hidden. The scan only
	# runs at 0.2 s — this is the fast path for boarding a car or dying.
	if _prompt != null and is_instance_valid(_prompt) and _prompt.visible:
		var ch := _character()
		if ch == null or _health(ch) <= 0.0:
			_near = -1
			_prompt.visible = false
	for i in range(_audio.size() - 1, -1, -1):
		var d := _audio[i]
		d["left"] = float(d["left"]) - delta
		var p: Variant = d["p"]
		if not (p is AudioStreamPlayer3D) or not is_instance_valid(p):
			_audio.remove_at(i)
		elif float(d["left"]) <= 0.0:
			(p as AudioStreamPlayer3D).stop()
			(p as AudioStreamPlayer3D).queue_free()
			_audio.remove_at(i)
	for i in range(_jets.size() - 1, -1, -1):
		var d := _jets[i]
		d["left"] = float(d["left"]) - delta
		var n: Variant = d["node"]
		if not (n is GPUParticles3D) or not is_instance_valid(n):
			_jets.remove_at(i)
			continue
		var jet := n as GPUParticles3D
		if float(d["left"]) <= JET_TAIL and jet.emitting:
			jet.emitting = false  # let the last drops land before the free
		if float(d["left"]) <= 0.0:
			jet.queue_free()
			_jets.remove_at(i)


## A playing AudioStreamPlayer3D at engine quit leaks its stream in 4.7.1 —
## stop everything still ringing on teardown (vehicle_audio does the same).
func _exit_tree() -> void:
	for d in _audio:
		var p: Variant = d["p"]
		if p is AudioStreamPlayer3D and is_instance_valid(p):
			(p as AudioStreamPlayer3D).stop()


# ============================== UI ===========================================
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
	_prompt.visible = false
	_ui.add_child(_prompt)


func _set_near(idx: int) -> void:
	if idx == _near:
		return
	_near = idx
	if _prompt == null or not is_instance_valid(_prompt):
		return
	if idx < 0:
		_prompt.visible = false
		return
	_prompt.text = ZING_PROMPT if str(_stations[idx]["kind"]) == "zing" else ATM_PROMPT
	_prompt.visible = true


# ============================== BUILD HELPERS ================================
func _box_mesh(parent: Node, size: Vector3, pos: Vector3, col: Color,
		emissive: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.2
	mi.material_override = m
	parent.add_child(mi)


## Faceplate lettering, fit to the panel. M22: measured, not estimated (see
## `sign_kit.gd`), and STENCIL — a vending faceplate is small wide-tracked
## machine type, and its outline is now a ratio of the size instead of a flat
## 10 px that at this scale was thicker than the strokes it was outlining.
## pixel_size 0.005: machine-scale type.
func _face_label(parent: Node, text: String, pos: Vector3, desired: int,
		max_w: float, col: Color) -> void:
	# emissive-looking: bright cream over the dark cabinet
	var lbl := SIGN.make(text, SIGN.STENCIL, col, max_w, 0.0, desired, 0.005)
	lbl.position = pos
	parent.add_child(lbl)


# ============================== AUDIO ========================================
## Vending thunk: a sine ping with a fast exponential decay; the short attack
## ramp kills the DC pop.
func _build_click() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(CLICK_SAMPLES)
	for i in CLICK_SAMPLES:
		var t := float(i) / float(MIX_RATE)
		var attack := minf(float(i) / 24.0, 1.0)
		samples[i] = 0.6 * sin(TAU * CLICK_HZ * t) * exp(-CLICK_DECAY * t) * attack
	return _wav(samples, false)


## Two-tone bank alarm. Each 1/6 s segment holds whole cycles of its tone
## (clipped sine -> square-ish), so segment joins and the loop point are all
## zero crossings. Two segments = one 3 Hz alternation.
func _build_alarm_loop() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(ALARM_SEG_SAMPLES * 2)
	for seg in 2:
		var cycles := float(ALARM_CYCLES[seg])
		for i in ALARM_SEG_SAMPLES:
			var ph := TAU * cycles * float(i) / float(ALARM_SEG_SAMPLES)
			samples[seg * ALARM_SEG_SAMPLES + i] = clampf(3.0 * sin(ph), -1.0, 1.0) * ALARM_GAIN
	return _wav(samples, true)


func _wav(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	if looping:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Positioned player riding `parent`, stopped + freed after `secs`. The
## tree_exiting hookup covers parents that despawn (4.7.1 leaks a playing
## stream at quit); _exit_tree covers our own teardown.
func _play_on(parent: Node, stream: AudioStreamWAV, secs: float,
		db: float, unit: float, max_dist: float) -> void:
	if parent == null or not is_instance_valid(parent) or stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = max_dist
	p.volume_db = db
	parent.add_child(p)
	p.tree_exiting.connect(p.stop)
	p.play()
	_audio.append({"p": p, "left": secs})


# ============================== PLUMBING =====================================
func _city() -> Node3D:
	var c: Variant = main_ref.get("city") if main_ref != null else null
	return c if c is Node3D and is_instance_valid(c) \
		and (c as Node).is_inside_tree() else null


## The walking avatar — null while driving, dead, or absent (prompt contract:
## on-foot only).
func _character() -> Node3D:
	if main_ref == null or main_ref.get("on_foot") != true:
		return null
	var c: Variant = main_ref.get("character")
	return c if c is Node3D and is_instance_valid(c) \
		and (c as Node).is_inside_tree() else null


func _health(ch: Node) -> float:
	var hp: Variant = ch.get("health")
	return float(hp) if (hp is float or hp is int) else FULL_HEALTH


func _flash(text: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("flash"):
		repo.call("flash", text)  # the one flash line in the game; repo owns it


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null
