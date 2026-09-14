extends Node
## MISSION: COMIN' DOWN (D-064) — story bible §7 #4: "earn Candyland respect in a
## reverse-race: a slab cruise where speed LOSES, ending in a takeover as the
## Street Racing Task Force escalates tier by tier." Built from what exists: the
## Candyland strip (slab_cruise), the Candyland Slab (data/vehicles/slab.json),
## the heat ladder (police), the mission kit. Roll up to the CANDYLAND C.C. board
## at the strip's west gate IN THE SLAB, slow. Three passes gate to gate under
## the break speed; each pass lights a star and the Task Force rides your
## bumper (police tails a slow driver at low heat — D-064). Then the takeover:
## park on the lot, and slide out — the contract completes when the law loses
## you. Candyland pays in respect; the club tips.
## IDLE -> CRUISE -> TAKEOVER -> SLIDE_OUT -> COMPLETE (cooldown), repeatable.

const BEACON := preload("res://scripts/world/beacon_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")
const BOARD_POS := Vector3(296.0, 0.0, 503.0)   # south of the strip's west gate (kerb 490)
const BOARD_RADIUS := 8.0; const BOARD_MAX_SPEED := 3.0
const SLAB_NAME := "Candyland Slab"
const BAND_X := Vector2(300.0, 780.0); const BAND_Z := Vector2(464.0, 490.0)   # slab_cruise's strip
const GATE_W := 312.0; const GATE_E := 768.0    # a pass: gate to gate
const BREAK_SPEED := 13.0                        # slab_cruise's combo-killer (~29 mph)
const OFF_STRIP_SECONDS := 20.0
const TAKEOVER_POS := Vector3(340.0, 0.0, 522.0); const TAKEOVER_RADIUS := 10.0; const TAKEOVER_MAX_SPEED := 1.5
const RESPECT_PER_PASS := 4; const RESPECT_PER_TICK := 1; const RESPECT_BREAK := -2
const PAYOUT := 250
const COOLDOWN_SECONDS := 45.0
const HEAT_PER_PASS := 1
const NOT_SLAB_EVERY := 12.0
const CANDY := Color(0.86, 0.36, 0.72)
const SPEAKER := "CANDYLAND C.C."
const OBJECTIVE_FONT := 18

enum State { IDLE, CRUISE, TAKEOVER, SLIDE_OUT, COMPLETE }

var main_ref: Node = null
var state: State = State.IDLE
var passes_needed := 3                # PUBLIC (probe may shorten the night)
var passes := 0
var _dir := 0                          # +1 east, -1 west
var _breaks := 0; var _over := false
var _off_t := 0.0; var _ticks := 0; var _tier := 0
var _start_t := 0.0; var _cooldown_t := 0.0; var _not_slab_t := 0.0
var _strip: Node = null
var _beam: Node3D = null
var _ui: CanvasLayer = null; var _objective: Label = null


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false)
		return
	_build_board(); _build_ui()


func _physics_process(delta: float) -> void:
	if main_ref == null: return
	_bind_strip()
	var pv := _player()
	match state:
		State.IDLE: _tick_idle(pv, delta)
		State.CRUISE: _tick_cruise(pv, delta)
		State.TAKEOVER: _tick_takeover(pv)
		State.SLIDE_OUT:
			if _heat() == 0: _complete()
		State.COMPLETE:
			_cooldown_t -= delta
			if _cooldown_t <= 0.0: state = State.IDLE
	if state != State.IDLE and state != State.COMPLETE:
		var of := _peer("on_foot")
		if of != null and of.has_method("player_down") and of.call("player_down") == true:
			_abort("The night's over. Candyland saw it. Come back.")


func _tick_idle(pv: RigidBody3D, delta: float) -> void:
	_not_slab_t = maxf(_not_slab_t - delta, 0.0)
	if pv == null: return
	var p := pv.global_position
	if Vector2(p.x - BOARD_POS.x, p.z - BOARD_POS.z).length() > BOARD_RADIUS \
			or absf(p.y - BOARD_POS.y) > 4.0 or pv.linear_velocity.length() > BOARD_MAX_SPEED:
		return
	if str(pv.get("display_name")) != SLAB_NAME:
		if _not_slab_t <= 0.0:
			_not_slab_t = NOT_SLAB_EVERY
			_say("Nice truck. Come back in the slab — TAB runs through your rigs.")
		return
	_start()


func _start() -> void:
	passes = 0; _dir = 1; _breaks = 0; _over = false; _off_t = 0.0; _ticks = 0
	_tier = _heat(); _start_t = Time.get_ticks_msec() / 1000.0
	state = State.CRUISE
	_say("Comin' down. Three passes, gate to gate, trunk up, elbows out. Keep it under thirty — speed loses here.", 6.0)
	_say("The Task Force will show. They ride your bumper; you don't ride the gas.", 4.5)


func _tick_cruise(pv: RigidBody3D, delta: float) -> void:
	if pv == null: return
	if str(pv.get("display_name")) != SLAB_NAME:
		_abort("You got out of the slab. The strip's for slabs.")
		return
	var p := pv.global_position
	var in_band := p.z >= BAND_Z.x and p.z <= BAND_Z.y and p.x >= BAND_X.x - 30.0 and p.x <= BAND_X.y + 30.0
	if not in_band:
		_off_t += delta
		if _off_t >= OFF_STRIP_SECONDS:
			_abort("You left the strip. Next time.")
		return
	_off_t = 0.0
	var speed := pv.linear_velocity.length()
	if speed > BREAK_SPEED and not _over:
		_over = true; _breaks += 1
		_say("Speed loses. Bring it down.", 3.0)
	elif speed < BREAK_SPEED - 2.0:
		_over = false
	if (_dir > 0 and p.x >= GATE_E) or (_dir < 0 and p.x <= GATE_W):
		_dir = -_dir
		passes += 1
		var pol := _peer("police")
		if pol != null and pol.has_method("add_heat"):
			pol.call("add_heat", HEAT_PER_PASS, "STREET RACING TASK FORCE")
		_tier = maxi(_tier, _heat())
		match passes:
			1: _say("That's one. Task Force is on the scanner. Let 'em look.", 4.0)
			2: _say("Two. They'll light you up now. Don't run — runnin's what they want.", 4.5)
			_: _say("Three. The whole strip saw it. Bring it to the lot, trunk up.", 4.5)
		if passes >= passes_needed:
			state = State.TAKEOVER


func _tick_takeover(pv: RigidBody3D) -> void:
	if pv == null: return
	var p := pv.global_position
	if Vector2(p.x - TAKEOVER_POS.x, p.z - TAKEOVER_POS.z).length() <= TAKEOVER_RADIUS \
			and pv.linear_velocity.length() <= TAKEOVER_MAX_SPEED:
		state = State.SLIDE_OUT
		_say("Takeover. Now slide out and lose 'em. Slow is done — now you drive.", 5.0)
		if _heat() == 0: _complete()


func _complete() -> void:
	var took := Time.get_ticks_msec() / 1000.0 - _start_t
	var respect := maxi(RESPECT_PER_PASS * passes + RESPECT_PER_TICK * _ticks + RESPECT_BREAK * _breaks, 1)
	var board := _peer("repo_board")
	if board != null:
		if board.has_method("add_respect"): board.call("add_respect", respect, "COMIN' DOWN")
		if board.has_method("add_money"): board.call("add_money", PAYOUT, "THE CLUB'S THANKS")
	var rows: Array = [
		["PASSES", "%d/%d" % [passes, passes_needed]], ["BREAKS", str(_breaks)],
		["TASK FORCE TIER", str(_tier)], ["RESPECT", "+%d" % respect],
		["THE CLUB'S THANKS", "$%d" % PAYOUT], ["TIME", "%d:%02d" % [int(took) / 60, int(took) % 60]]]
	var medal := "GOLD" if _breaks == 0 else ("SILVER" if _breaks <= 2 else "BRONZE")
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("card"):
		kit.call("card", "COMIN' DOWN", "CANDYLAND C.C. · THE SLOW LANE", rows, medal)
	_say("Candyland remembers. Come down again when the sun's gone.", 5.0)
	state = State.COMPLETE; _cooldown_t = COOLDOWN_SECONDS


func _abort(line: String) -> void:
	state = State.IDLE
	_say(line, 4.5)


## slab_cruise's ticks are the score; bind lazily, it loads after this file.
func _bind_strip() -> void:
	if _strip != null and is_instance_valid(_strip): return
	_strip = _peer("slab_cruise")
	if _strip != null and _strip.has_signal("strip_tick") and not _strip.is_connected("strip_tick", _on_tick):
		_strip.connect("strip_tick", _on_tick)


func _on_tick(_amount: int) -> void:
	if state == State.CRUISE: _ticks += 1


# ============================== THE BOARD ====================================
func _build_board() -> void:
	_beam = BEACON.beacon(CANDY, 14.0, 2.0, 0.28, 1.3, 4.0, 0.12)
	_beam.position = BOARD_POS
	add_child(_beam)
	var pole := StaticBody3D.new()
	var pcol := CollisionShape3D.new(); var pshape := BoxShape3D.new()
	pshape.size = Vector3(0.22, 2.7, 0.22); pcol.shape = pshape; pole.add_child(pcol)
	var pm := MeshInstance3D.new(); var pb := BoxMesh.new(); pb.size = pshape.size; pm.mesh = pb
	var pmat := StandardMaterial3D.new(); pmat.albedo_color = Color(0.5, 0.5, 0.5); pmat.roughness = 0.8
	pm.material_override = pmat; pole.add_child(pm)
	pole.position = BOARD_POS + Vector3(-9.0, 1.35, 0); add_child(pole)
	var bmat := StandardMaterial3D.new(); bmat.albedo_color = CANDY; bmat.roughness = 0.6
	bmat.emission_enabled = true; bmat.emission = CANDY; bmat.emission_energy_multiplier = 0.6
	var board := MeshInstance3D.new(); var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.15, 1.0, 4.6); board.mesh = bmesh; board.material_override = bmat
	board.position = BOARD_POS + Vector3(-9.0, 3.2, 0); add_child(board)
	var sign := SIGN.make("CANDYLAND C.C.", SIGN.FASCIA, Color(0.10, 0.04, 0.09), 4.40, 0.82, 60, 0.0075)
	sign.position = BOARD_POS + Vector3(-8.9, 3.2, 0)
	sign.rotation.y = PI * 0.5   # front normal east, toward the strip's gate
	add_child(sign)


func _process(_delta: float) -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.visible = state == State.IDLE
	if _objective == null: return
	_objective.visible = state != State.IDLE
	_objective.text = _objective_text()


func _objective_text() -> String:
	match state:
		State.CRUISE:
			var pv := _player()
			var sp := pv.linear_velocity.length() * 2.237 if pv != null else 0.0
			return "COMIN' DOWN · PASS %d/%d · %s · %d MPH" % [passes + 1, passes_needed, "EAST" if _dir > 0 else "WEST", int(sp)]
		State.TAKEOVER: return "TAKEOVER — PARK ON THE LOT, TRUNK UP"
		State.SLIDE_OUT: return "SLIDE OUT — LOSE THE TASK FORCE"
		State.COMPLETE: return "CANDYLAND RE-ARM %ds" % int(ceilf(_cooldown_t))
	return ""


func _build_ui() -> void:
	_ui = CanvasLayer.new(); _ui.layer = 14
	add_child(_ui)
	_objective = Label.new()
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_objective.offset_left = -420.0; _objective.offset_right = 420.0
	_objective.offset_top = -240.0; _objective.offset_bottom = -210.0
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_font_size_override("font_size", OBJECTIVE_FONT)
	_objective.add_theme_color_override("font_color", CANDY.lightened(0.35))
	_objective.add_theme_constant_override("outline_size", 6)
	_objective.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.visible = false; _ui.add_child(_objective)


# ============================== PLUMBING =====================================
func _say(line: String, seconds := 4.5) -> void:
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("say"): kit.call("say", SPEAKER, line, seconds)


func _heat() -> int:
	var pol := _peer("police")
	var hv: Variant = pol.get("heat") if pol != null else null
	return int(hv) if hv is int else 0


func _player() -> RigidBody3D:
	if main_ref == null or main_ref.get("on_foot") == true: return null
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree(): return v
	return null


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null
