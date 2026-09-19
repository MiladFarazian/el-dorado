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

# ---------------------------- THE LOT (the crowd) ----------------------------
# D-064's open item: "the takeover is a parking spot, not a crowd". The club
# shows up — people first, rides second, a string of bulbs if the sun's gone.
# Everything here is PUBLIC API only: pedestrians' follower verbs, the body
# builder, the beacon-free mesh primitives. Nothing reaches into a peer.
const PEDS := preload("res://scripts/systems/pedestrians.gd")
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const CLUB_MIN := 10; const CLUB_MAX := 14   # how many come out (seeded per takeover)
const CLUB_SPAWN_R := 13.0     # m from the lot centre: he walks on from out here
const CLUB_MARK_R := 4.6       # his marker; FOLLOW_STOP (2.8 m) short of it is where he stands
const CLUB_PER_TICK := 2       # spawned per physics frame — a crowd arrives, it does not pop
const CLUB_STAND_S := 600.0    # follower TTL: longer than any takeover
const CLUB_NEAR := 180.0       # only fill when the player is this close (peds despawn at 260)
const CLUB_CLEAR := 4.0        # never spawn this close to the player's rig
const CLUB_Y := 0.875          # PEDS.PED_HALF over the lot's slab (y = 0)
const FACE_WITHIN := 10.0      # m: who turns to the slab when it pulls in (the settled ones)
const FACE_HOLD := 2.4         # m: marker parked inside FOLLOW_STOP, so he turns and stays put
const HONK_RADIUS := 18.0      # the strip steps back as the slab rolls through
const RIDE_COUNT := 4
const RIDE_R := 16.5           # the four club rides, outboard of the people
const RIDE_ANGLES: Array[float] = [30.0, 90.0, 150.0, 210.0]   # east-south round to west; north stays open
const RIDE_SIZE := Vector3(1.9, 1.05, 4.4)
const RIDE_WHEEL := 0.32; const RIDE_RIDE_H := 0.85; const RIDE_MASS := 1300.0
const CANDY_PAINT: Array[Color] = [
	Color(0.62, 0.05, 0.10),   # candy apple
	Color(0.30, 0.11, 0.52),   # grape
	Color(0.05, 0.44, 0.45),   # teal
	Color(0.72, 0.56, 0.13)]   # gold
const BULB_HOUR := Vector2(19.0, 6.0)    # after 19:00 or before 06:00: the string goes up
const BULB_SPAN := 28.0; const BULB_TOP := 5.2; const BULB_SAG := 0.40
const BULB_COUNT := 26; const BULB_SIZE := 0.17
const BULB_COLORS: Array[Color] = [
	Color(1.0, 0.36, 0.78), Color(1.0, 0.78, 0.22),
	Color(0.32, 0.92, 0.88), Color(0.68, 0.44, 1.0)]
const CROWD_LINE_EVERY := 9.0
const RESPECT_ARRIVAL := 2; const RESPECT_HIT := -4
const LOT_SEED := 0xCA9D1A     # seeded: two boots put the same club on the same lot

## The club is family, not the joke. Warm, specific, the strip's own register.
const ARRIVE_LINES: Array[String] = [
	"Lot's ours tonight. Bring it in slow — let 'em hear that trunk.",
	"Y'all move them lawn chairs, Book's comin' in. Watch the paint.",
	"That candy hittin' different under these lights. Mmm.",
	"Grandma made a pan of somethin'. It's in Reggie's trunk, go on.",
	"Swang it wide on the way in. We got all night, ain't nobody rushin' you.",
	"Elbows out. That's how my daddy brought one down this same street.",
	"Every third Sunday, same lot, same people. Now you're on the list.",
	"Cut it off right there. Let it sit. Let 'em look."]
const SLIDE_LINES: Array[String] = [
	"Go on. We got the lot.",
	"They want you, not us. Slide out clean and don't look back.",
	"Take the frontage. Lights off past the second light.",
	"We'll still be here when you circle back. We always are."]

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
# --- the lot ---
var _lot: Node3D = null                      # every spawned prop hangs here; freed as one
var _club: Array[RigidBody3D] = []           # follower bodies: pedestrians owns them, we free them
var _marks: Array[Node3D] = []               # one marker per member: a loose ring, never a pile
var _lot_rng := RandomNumberGenerator.new()
var _want := 0; var _crowd_peak := 0
var _arrived := false; var _hit_charged := false
var _line_t := 0.0; var _arrive_i := 0; var _slide_i := 0
var _arrive_pool: Array[String] = []


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
	_lot_sync(delta)


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
			_lot_open()


func _tick_takeover(pv: RigidBody3D) -> void:
	if pv == null: return
	var p := pv.global_position
	if Vector2(p.x - TAKEOVER_POS.x, p.z - TAKEOVER_POS.z).length() <= TAKEOVER_RADIUS \
			and pv.linear_velocity.length() <= TAKEOVER_MAX_SPEED:
		state = State.SLIDE_OUT
		_say("Takeover. Now slide out and lose 'em. Slow is done — now you drive.", 5.0)
		_lot_arrive()
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
		["TASK FORCE TIER", str(_tier)], ["THE LOT", "%d came out" % _crowd_peak],
		["RESPECT", "+%d" % respect],
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
	_objective.visible = false   # D-155: the HUD draws this label's text; the mission never does
	_objective.text = _objective_text()


func _objective_text() -> String:
	match state:
		State.CRUISE:
			var pv := _player()
			var sp := pv.linear_velocity.length() * 2.237 if pv != null else 0.0
			return "COMIN' DOWN · PASS %d/%d · %s · %d MPH" % [passes + 1, passes_needed, "EAST" if _dir > 0 else "WEST", int(sp)]
		State.TAKEOVER: return "TAKEOVER — PARK ON THE LOT, TRUNK UP"
		State.SLIDE_OUT: return "SLIDE OUT — LOSE THE TASK FORCE"
		State.COMPLETE: return ""   # D-071: one objective line on screen
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


# ============================== THE LOT ======================================
## The takeover is a crowd, not a parking spot (D-064's open item). The club
## gathers the moment the third pass lands, holds the lot through the slide-out,
## and goes home when the night ends — however it ends.
func _lot_sync(delta: float) -> void:
	if state == State.TAKEOVER or state == State.SLIDE_OUT:
		if _lot == null: _lot_open()
		_lot_fill()
		_lot_talk(delta)
		_lot_watch()
	elif _lot != null:
		_lot_close()


func _lot_open() -> void:
	if _lot != null: return
	_lot = Node3D.new(); _lot.name = "CandylandLot"
	add_child(_lot)
	_lot_rng.seed = LOT_SEED
	_want = _lot_rng.randi_range(CLUB_MIN, CLUB_MAX)
	_crowd_peak = 0; _arrived = false; _hit_charged = false
	_line_t = 0.0; _arrive_i = 0; _slide_i = 0
	_arrive_pool = ARRIVE_LINES.duplicate()
	for i in range(_arrive_pool.size() - 1, 0, -1):   # seeded shuffle: the same order on every boot
		var j := _lot_rng.randi_range(0, i)
		var tmp := _arrive_pool[i]; _arrive_pool[i] = _arrive_pool[j]; _arrive_pool[j] = tmp
	_build_marks()
	_build_rides()
	_build_bulbs()


## Freeing is ours: pedestrians owns the follower bodies but drops a freed entry
## on its next _validate, so queue_free is the whole contract.
func _lot_close() -> void:
	for i in _club.size():
		var bv: Variant = _club[i]   # D-068: validity BEFORE the cast, every time
		if is_instance_valid(bv): (bv as Node).queue_free()
	_club.clear(); _marks.clear()
	if _lot != null and is_instance_valid(_lot): _lot.queue_free()
	_lot = null
	_want = 0; _arrived = false; _hit_charged = false


## PUBLIC (probe): club members standing on the lot right now.
func crowd_count() -> int:
	var n := 0
	for i in _club.size():
		var bv: Variant = _club[i]
		if is_instance_valid(bv) and (bv as Node).is_inside_tree(): n += 1
	return n


## One marker per member on a small inner ring: the follower stops FOLLOW_STOP
## (2.8 m) short of its target, so a ring of markers at 4.6 m becomes a ring of
## people at ~7.4 m — a loose circle around the slab's spot, never a pile on it.
func _build_marks() -> void:
	for i in _want:
		var a := TAU * (float(i) + _lot_rng.randf_range(-0.22, 0.22)) / float(_want)
		var r := CLUB_MARK_R + _lot_rng.randf_range(-0.7, 0.9)
		var m := Node3D.new(); m.name = "Mark%d" % i
		m.position = TAKEOVER_POS + Vector3(cos(a) * r, CLUB_Y, sin(a) * r)
		_lot.add_child(m)
		_marks.append(m)


## A few per physics tick, from out past the rides, walking in. Topped up while
## the lot holds so a member lost to the ped budget comes back. Never inside the
## player's rig, never on the centre where the slab parks.
func _lot_fill() -> void:
	for i in range(_club.size() - 1, -1, -1):
		var bv: Variant = _club[i]
		if not is_instance_valid(bv) or not (bv as Node).is_inside_tree():
			_club.remove_at(i)
	_crowd_peak = maxi(_crowd_peak, _club.size())
	if _club.size() >= _want or _marks.is_empty(): return
	var peds := _peer("pedestrians")
	if peds == null or not peds.has_method("spawn_follower_at"): return
	var pv := _player()
	var here: Vector3 = pv.global_position if pv != null else Vector3.ZERO
	if pv == null or here.distance_to(TAKEOVER_POS) > CLUB_NEAR: return
	var made := 0
	while made < CLUB_PER_TICK and _club.size() < _want:
		var idx := _club.size()
		var mark: Node3D = _marks[idx % _marks.size()]
		var out := mark.global_position - TAKEOVER_POS; out.y = 0.0
		var head := out.normalized() if out.length() > 0.05 else Vector3.FORWARD
		var pos := TAKEOVER_POS + head * CLUB_SPAWN_R
		pos.y = CLUB_Y
		if pos.distance_to(here) < CLUB_CLEAR: return   # he'd land in the slab: next frame
		var body: Variant = peds.call("spawn_follower_at", pos, -head, mark, CLUB_STAND_S)
		if not (body is RigidBody3D) or not is_instance_valid(body): return
		_club.append(body as RigidBody3D)
		made += 1
	_crowd_peak = maxi(_crowd_peak, _club.size())


## One line at a time, nine seconds apart at most: a crowd murmurs, it does not
## monologue. The arrival pool runs while he's rolling in; the slide-out pool
## the moment he parks.
func _lot_talk(delta: float) -> void:
	_line_t -= delta
	if _line_t > 0.0: return
	_line_t = CROWD_LINE_EVERY
	if state == State.SLIDE_OUT:
		if _slide_i >= SLIDE_LINES.size(): return
		_say(SLIDE_LINES[_slide_i], 4.2)
		_slide_i += 1
		return
	if _arrive_i >= _arrive_pool.size(): return
	_say(_arrive_pool[_arrive_i], 4.2)
	_arrive_i += 1


## The slab hit one of ours. pedestrians already docks the ordinary strike; this
## is Candyland's own, charged once a night.
func _lot_watch() -> void:
	if _hit_charged: return
	var peds := _peer("pedestrians")
	if peds == null or not peds.has_method("state_of"): return
	for i in _club.size():
		var bv: Variant = _club[i]
		if not is_instance_valid(bv) or not (bv as Node).is_inside_tree(): continue
		if int(peds.call("state_of", bv)) != PEDS.DOWN: continue
		# D-071: only Book's own rig is on Book's account — the Task Force
		# ploughing through the club is their crime, not his.
		if peds.has_method("downed_by_player") and not bool(peds.call("downed_by_player", bv)): continue
		_hit_charged = true
		var board := _peer("repo_board")
		if board != null and board.has_method("add_respect"):
			board.call("add_respect", RESPECT_HIT, "HIT ONE OF OURS")
		_say("Hey! That's somebody's granddaddy standin' there. Watch it.", 4.5)
		return


## The slab is on the lot. The strip salutes, the club turns to look, and
## Candyland marks the board for showing up at all.
func _lot_arrive() -> void:
	if _arrived: return
	_arrived = true
	_line_t = 0.0
	var board := _peer("repo_board")
	if board != null and board.has_method("add_respect"):
		board.call("add_respect", RESPECT_ARRIVAL, "THE CLUB SHOWED")
	var pv := _player()
	if pv == null: return
	var peds := _peer("pedestrians")
	if peds != null and peds.has_method("honk_at"):
		peds.call("honk_at", pv, HONK_RADIUS)   # the strip steps back as he rolls through
	_face_club(pv.global_position)


## Turning a follower is a matter of where his marker is: _update_follow points
## him at it and only walks if it is further than FOLLOW_STOP. Park the marker
## FACE_HOLD in front of him, on the line to the slab, and he turns and stands.
## Only the settled ones — anyone still walking in keeps walking in.
func _face_club(at: Vector3) -> void:
	for i in _club.size():
		var bv: Variant = _club[i]
		if not is_instance_valid(bv) or not (bv as Node).is_inside_tree(): continue
		var here := (bv as Node3D).global_position
		if Vector2(here.x - TAKEOVER_POS.x, here.z - TAKEOVER_POS.z).length() > FACE_WITHIN: continue
		if i >= _marks.size(): continue
		var mark := _marks[i]
		if not is_instance_valid(mark): continue
		var look := at - here; look.y = 0.0
		if look.length() < 0.2: continue
		mark.global_position = here + look.normalized() * FACE_HOLD


## Four club rides nosed in around the lot's edge, candy on all four. Frozen
## display shells: they are somebody's baby, not scenery and NOT towable — the
## one group this mission will never add is "towable". Nobody hooks the club.
func _build_rides() -> void:
	for i in RIDE_COUNT:
		var a := deg_to_rad(RIDE_ANGLES[i % RIDE_ANGLES.size()])
		var r := RIDE_R + _lot_rng.randf_range(-0.8, 0.8)
		var pos := TAKEOVER_POS + Vector3(cos(a) * r, RIDE_RIDE_H, sin(a) * r)
		var fwd := (TAKEOVER_POS - pos); fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
		var car := RigidBody3D.new()
		car.name = "ClubRide%d" % i
		car.mass = RIDE_MASS
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.freeze = true
		var pm := PhysicsMaterial.new(); pm.friction = 0.9
		car.physics_material_override = pm
		car.set_meta("carjack_has_driver", false)
		var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
		shape.size = RIDE_SIZE; col.shape = shape; car.add_child(col)
		var vis := Node3D.new(); car.add_child(vis)
		BODY_BUILDER.build(vis, "sedan", RIDE_SIZE, CANDY_PAINT[i % CANDY_PAINT.size()])
		_ride_wheels(car)
		car.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
		_lot.add_child(car)


func _ride_wheels(car: RigidBody3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = RIDE_WHEEL; mesh.bottom_radius = RIDE_WHEEL
	mesh.height = 0.24; mesh.radial_segments = 18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09); mat.roughness = 0.9
	var zoff := RIDE_SIZE.z * 0.5 - RIDE_WHEEL - 0.7
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new()
		w.mesh = mesh; w.material_override = mat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = Vector3(c.x * (RIDE_SIZE.x * 0.5 - 0.075), RIDE_WHEEL - RIDE_RIDE_H, c.y * zoff)
		car.add_child(w)


## After dark the lot gets a string: two poles east-west of the centre, a wire
## between them, and one MultiMesh of small unshaded bulbs hung under it in the
## four candy colours. Poles carry NO collision — the probe teleports the slab
## onto this lot and nothing of ours may be in its way. D-059: a script-built
## MultiMesh reads an EMPTY AABB and is culled everywhere, so set custom_aabb.
func _build_bulbs() -> void:
	if not _after_dark(): return
	var half := BULB_SPAN * 0.5
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.20, 0.20, 0.22); pmat.roughness = 0.85
	for sx: float in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var pb := BoxMesh.new(); pb.size = Vector3(0.16, BULB_TOP, 0.16)
		pole.mesh = pb; pole.material_override = pmat
		pole.position = TAKEOVER_POS + Vector3(sx * half, BULB_TOP * 0.5, 0.0)
		_lot.add_child(pole)
	var wire := MeshInstance3D.new()
	var wb := BoxMesh.new(); wb.size = Vector3(BULB_SPAN, 0.035, 0.035)
	wire.mesh = wb; wire.material_override = pmat
	wire.position = TAKEOVER_POS + Vector3(0.0, BULB_TOP - 0.08, 0.0)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lot.add_child(wire)
	var bulb := BoxMesh.new()
	bulb.size = Vector3(BULB_SIZE, BULB_SIZE * 1.3, BULB_SIZE)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.vertex_color_use_as_albedo = true
	bmat.albedo_color = Color(1, 1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bulb
	mm.instance_count = BULB_COUNT
	var bounds := AABB(TAKEOVER_POS, Vector3.ZERO)
	for i in BULB_COUNT:
		var t := float(i) / float(BULB_COUNT - 1)
		var y := BULB_TOP - 0.22 - BULB_SAG * sin(PI * t)
		var o := TAKEOVER_POS + Vector3(lerpf(-half, half, t), y, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, o))
		mm.set_instance_color(i, BULB_COLORS[i % BULB_COLORS.size()])
		bounds = bounds.expand(o)
	mm.custom_aabb = bounds.grow(1.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bmat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lot.add_child(mmi)


## sky_weather's clock, read-only. No peer, no clock: treat it as daylight.
func _after_dark() -> bool:
	var sky := _peer("sky_weather")
	if sky == null: return false
	var tv: Variant = sky.get("time_of_day")
	if not (tv is float): return false
	var h := tv as float
	return h >= BULB_HOUR.x or h < BULB_HOUR.y
