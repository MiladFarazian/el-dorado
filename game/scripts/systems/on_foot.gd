extends Node
## ON FOOT — the vehicle/character mode switch. E ("enter_exit") steps Book
## Reyes out at the driver door (inheriting the truck's velocity — exiting at
## speed is allowed, comedy is physics) and back in within ENTER_RANGE. Owns
## main.character / main.on_foot, the mouse-capture sanity valve (ESC), and the
## death -> "BLESS YOUR HEART." card -> County General respawn loop.
## ENTIRELY INERT in smoke mode. Peers bound lazily via main.systems; every
## reference is null-checked (contract).

const CHARACTER_SCRIPT := preload("res://scripts/player/player_character.gd")
const REPO := preload("res://scripts/systems/repo_board.gd")  # PAD_CENTER: the impound lot

# ============================== TUNABLES =====================================
const EXIT_SIDE := 2.3               # driver door: -basis.x * this from origin (m)
const EXIT_UP := 0.4                 # spawn lift so feet never start in the slab (m)
const EXIT_BEHIND := 3.9             # fallback spot behind the truck (m)
const ENTER_RANGE := 3.6             # E boards the vehicle within this (m)
const DEBOUNCE := 0.4                # s before E can fire again, both directions
const CLEAR_PROBE_SIZE := Vector3(0.5, 1.2, 0.4)  # slim stand-room probe box
const CLEAR_PROBE_Y := 0.9           # probe centre above the candidate feet (m)
const DEATH_TIME := 4.0              # s the death card holds before respawn
const DEATH_FADE := 0.45             # s vignette fade-in
const HOSPITAL_FEE := 300            # County General is not free
const WALKOUT_TIME := 1.4            # s Book walks himself out the ER doors
const HEAT_CLEAR := -10              # add_heat clamps at 0: guaranteed clean slate
const DEATH_FONT_SIZE := 84
const DEATH_SUB_FONT_SIZE := 22
const VIGNETTE_COLOR := Color(0.04, 0.01, 0.01, 0.86)
const DEATH_TEXT_COLOR := Color(0.91, 0.85, 0.68)  # cream on funeral dark

# ============================== STATE ========================================
var main_ref: Node = null
var _debounce := 0.0
var _death_active := false
var _death_t := 0.0
var _card_mode := "wasted"           # "wasted" (County General) or "busted" (Longhorn Impound)
var _pending_fine := 0
var _card_title: Label = null
var _card_sub: Label = null
var _ui: CanvasLayer = null
var _card_root: Control = null


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: fully inert — no UI, no spawns, no mouse changes
	_build_death_ui()


## Vehicle swaps are gated to !on_foot in main.gd, so there is nothing to
## re-point here; kept as an explicit no-op for the systems contract.
func on_vehicle_changed(_vehicle: Node) -> void:
	pass


func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_debounce = maxf(_debounce - delta, 0.0)
	# Defensive: the walking avatar vanished out from under us (freed by an
	# external force) -> fall back to vehicle mode instead of soft-locking.
	if _on_foot() and _character() == null and not _death_active:
		_board_vehicle(_vehicle())
		return
	# D-063: the ESC valve is checked BEFORE the death-card gate. It used to sit
	# below it, so for the 4 s the funeral card is up — the one moment a player
	# is most likely to reach for the mouse — the only way to release the cursor
	# was unreachable. Releasing the mouse is never a mode change and has no
	# business being gated behind one.
	if not main_ref.systems.has("session") and Input.is_action_just_pressed("ui_cancel"):
		# ESC sanity valve, in BOTH modes: the mouse is captured while driving
		# too now (it swings the chase boom and aims drive-bys), so the escape
		# hatch has to work behind the wheel as well.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if _death_active:
		return  # no mode changes mid-death-card
	if InputMap.has_action("enter_exit") and Input.is_action_just_pressed("enter_exit") \
			and _debounce <= 0.0:
		if _on_foot():
			_try_enter()
		else:
			_exit_vehicle()


func _process(delta: float) -> void:
	if not _death_active:
		return
	_death_t -= delta
	if _card_root != null and is_instance_valid(_card_root):
		_card_root.modulate.a = clampf((DEATH_TIME - _death_t) / DEATH_FADE, 0.0, 1.0)
	if _death_t <= 0.0:
		_respawn()


# ============================== EXIT / ENTER =================================
func _exit_vehicle() -> void:
	var veh := _vehicle()
	if veh == null:
		return
	var ch := CHARACTER_SCRIPT.new() as CharacterBody3D
	ch.name = "BookReyes"
	ch.set("main_ref", main_ref)
	main_ref.add_child(ch)
	ch.global_position = _pick_exit_pos(veh)
	var fwd := -veh.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.1:
		ch.rotation.y = atan2(-fwd.x, -fwd.z)  # step out facing the truck's way
	ch.velocity = veh.linear_velocity          # momentum carries out the door
	if ch.has_signal("died"):
		ch.connect("died", _on_character_died)
	main_ref.set("character", ch)
	main_ref.set("on_foot", true)
	veh.set("player_controlled", false)
	_point_camera(ch)
	# Enter the foot rig NOW so the very first physics tick reads a fresh
	# orbit_yaw (the camera's idle _process may lag a tick under load).
	var cam: Variant = main_ref.get("camera")
	if cam is Object and is_instance_valid(cam) and (cam as Object).has_method("_enter_foot_rig"):
		(cam as Object).call("_enter_foot_rig")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_debounce = DEBOUNCE


## E boards the nearest ride, whoever it belongs to. carjack owns the choice and
## the consequences (conversion, driver, heat) and hands back the body to sit
## in; if that system is missing or the handover fails we fall back to the M5
## behaviour — your own truck, within arm's reach.
func _try_enter() -> void:
	var ch := _character()
	if ch == null:
		return
	var cj := _peer("carjack")
	if cj != null and cj.has_method("find_target") and cj.has_method("claim"):
		var target: Variant = cj.call("find_target", ch)
		if target is Node3D and is_instance_valid(target):
			var taken: Variant = cj.call("claim", target)
			if taken is RigidBody3D and is_instance_valid(taken):
				_board_vehicle(taken)
				return
	var veh := _vehicle()
	if veh == null:
		return
	if ch.global_position.distance_to(veh.global_position) > ENTER_RANGE:
		return
	_board_vehicle(veh)


## Back to vehicle mode: free the avatar, hand the keys back, free the mouse.
## set_player_vehicle is what makes THIS car the one the game means by "the
## player" — it repoints camera/HUD and tells every system the body changed.
func _board_vehicle(veh: Node) -> void:
	var ch := _character()
	if ch != null:
		ch.queue_free()
	main_ref.set("character", null)
	main_ref.set("on_foot", false)
	if veh != null and is_instance_valid(veh):
		if main_ref.has_method("set_player_vehicle"):
			main_ref.call("set_player_vehicle", veh)
		veh.set("player_controlled", true)
		_point_camera(veh)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # driving keeps mouse look
	_debounce = DEBOUNCE


## Driver door first, passenger door second, behind the truck last — the cheap
## intersect check just wants stand-room that is not inside a wall or a junker.
func _pick_exit_pos(veh: RigidBody3D) -> Vector3:
	var base: Vector3 = veh.global_position + Vector3.UP * EXIT_UP
	var bx: Vector3 = veh.global_transform.basis.x
	var bz: Vector3 = veh.global_transform.basis.z
	var candidates: Array[Vector3] = [
		base - bx * EXIT_SIDE,       # driver door
		base + bx * EXIT_SIDE,       # nudge over: passenger side
		base + bz * EXIT_BEHIND,     # nudge back: behind the truck
		base + bz * EXIT_BEHIND + Vector3.UP * 1.2,  # nudge up: last resort
	]
	for c in candidates:
		if _spot_clear(veh, c):
			return c
	return candidates[2]  # geometry everywhere: behind the truck and good luck


func _spot_clear(veh: RigidBody3D, feet: Vector3) -> bool:
	var world := veh.get_world_3d()
	if world == null:
		return true
	var shape := BoxShape3D.new()
	shape.size = CLEAR_PROBE_SIZE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * CLEAR_PROBE_Y)
	q.exclude = [veh.get_rid()]
	return world.direct_space_state.intersect_shape(q, 1).is_empty()


# ============================== DEATH / RESPAWN ==============================
## PUBLIC (police_gunfire): cops hold fire while the funeral card is up.
func player_down() -> bool:
	return _death_active


## PUBLIC (police_gunfire): the ride was shot to pieces around Book while he
## refused to leave it. Same card, same $300, same trip home — works with or
## without a character in the world (there is none while driving).
func kill_player() -> void:
	_on_character_died()


## PUBLIC (arrest): the cuffs closed. Same card machinery as a death, different
## words, different destination — Book wakes on the Longhorn Impound lot beside
## the wrecker (D-056), `fine` lighter, heat gone, NOT healed and NOT repaired:
## the county fixes what the county shot; the impound fixes nothing.
func arrest(fine: int) -> void:
	if _death_active:
		return
	_card_mode = "busted"
	_pending_fine = fine
	if _card_title != null:
		_card_title.text = "BUSTED."
	if _card_sub != null:
		_card_sub.text = "LONGHORN IMPOUND. Bail $%d. The wrecker's on the lot." % fine
	_on_character_died()


func _on_character_died() -> void:
	if _death_active:
		return
	_death_active = true
	_death_t = DEATH_TIME
	if _ui != null and is_instance_valid(_ui):
		if _card_root != null and is_instance_valid(_card_root):
			_card_root.modulate.a = 0.0
		_ui.visible = true


## COUNTY GENERAL (M13, D-016): you wake up ON FOOT, walking out of the ER
## doors under your own power — the classic. The wrecker waits on the apron
## out front (dying two districts from it must never strand the repo job);
## whatever you had STOLEN stays wherever you died in it. Heat gone, $300
## lighter, patched to full. Falls back to the old in-truck respawn on a city
## build without the hospital contract.
func _respawn() -> void:
	_death_active = false
	if _ui != null and is_instance_valid(_ui):
		_ui.visible = false
	if _card_mode == "busted":
		_respawn_busted()
		return
	var hosp := _hospital_transforms()
	if hosp.is_empty():
		_respawn_in_truck()
	else:
		_respawn_at_hospital(hosp[0], hosp[1])
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", HEAT_CLEAR)
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", -HOSPITAL_FEE, "COUNTY GENERAL")
	# County General's lot fixes what the county shot — the $300 covers it.
	var guns := _peer("police_gunfire")
	if guns != null and guns.has_method("repair_all"):
		guns.call("repair_all")


## The impound lot is the repo pad (repo_board.PAD_CENTER, 14 x 10 m, flat):
## the wrecker parks on its west half facing the street, Book walks off the east.
func _respawn_busted() -> void:
	_card_mode = "wasted"
	if _card_title != null:
		_card_title.text = "BLESS YOUR HEART."
	if _card_sub != null:
		_card_sub.text = "COUNTY GENERAL patched you up — $%d. The wrecker's out front." % HOSPITAL_FEE
	var pad: Vector3 = REPO.PAD_CENTER
	var truck := Transform3D(Basis.IDENTITY, pad + Vector3(-3.5, 1.2, 0.0))
	var door := Transform3D(Basis.IDENTITY, pad + Vector3(2.0, 0.25, 0.0))
	var ch := _character()
	var hp := float(ch.get("health")) if ch != null and ch.get("health") is float else -1.0
	_respawn_at_hospital(door, truck)
	ch = _character()
	if hp >= 0.0 and ch != null and ch.has_method("take_damage"):
		var mh: Variant = ch.get("max_health")
		var top := float(mh) if (mh is float or mh is int) else 100.0
		ch.call("take_damage", maxf(top - hp, 0.0))  # the heal in there is undone: no patching at the impound
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", HEAT_CLEAR)
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", -_pending_fine, "LONGHORN IMPOUND")
	_pending_fine = 0


func _respawn_at_hospital(door: Transform3D, truck: Transform3D) -> void:
	# The wrecker first: park it on the apron and make it "the player's ride"
	# again, so Tab/HUD land on the truck, not on whatever you died in.
	var veh := _own_vehicle()
	if veh != null:
		if veh.has_method("reset_to"):
			veh.call("reset_to", truck)  # also zeroes velocities + wheel state
		else:
			veh.global_transform = truck
		if main_ref.has_method("set_player_vehicle"):
			main_ref.call("set_player_vehicle", veh)
		veh.set("player_controlled", false)  # nobody is behind the wheel yet
	var cur := _vehicle()
	if cur != null and cur != veh:
		cur.set("player_controlled", false)  # the stolen ride stays at the scene
	# The patient: re-use the avatar if the death happened on foot, spawn one
	# if it happened behind the wheel (there is no character while driving).
	var ch := _character()
	if ch == null:
		ch = CHARACTER_SCRIPT.new() as CharacterBody3D
		ch.name = "BookReyes"
		ch.set("main_ref", main_ref)
		main_ref.add_child(ch)
		if ch.has_signal("died"):
			ch.connect("died", _on_character_died)
	if ch.has_method("heal"):
		ch.call("heal", 1000.0)  # clamps to full
	ch.global_position = door.origin
	var fwd := -door.basis.z
	ch.rotation.y = atan2(-fwd.x, -fwd.z)
	ch.velocity = Vector3.ZERO
	main_ref.set("character", ch)
	main_ref.set("on_foot", true)
	_point_camera(ch)
	var cam: Variant = main_ref.get("camera")
	if cam is Object and is_instance_valid(cam) and (cam as Object).has_method("snap_foot_rig"):
		(cam as Object).call("snap_foot_rig", ch.rotation.y)
	if ch.has_method("begin_walkout"):
		ch.call("begin_walkout", WALKOUT_TIME)  # walks himself out the doors
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_debounce = DEBOUNCE


## Legacy respawn (pre-hospital cities): healed, home to the city spawn, back
## behind the wheel.
func _respawn_in_truck() -> void:
	var ch := _character()
	if ch != null and ch.has_method("heal"):
		ch.call("heal", 1000.0)  # clamps to full
	var veh := _own_vehicle()
	if veh == null:
		veh = _vehicle()
	var spawn := _spawn_transform()
	if veh != null:
		if veh.has_method("reset_to"):
			veh.call("reset_to", spawn)  # also zeroes velocities + wheel state
		else:
			veh.global_transform = spawn
	_board_vehicle(veh)  # frees the healed character back into the cab


## Hospital contract: [door, truck] transforms off the city, or [] without it.
func _hospital_transforms() -> Array:
	var city: Variant = main_ref.get("city") if main_ref != null else null
	if city is Node and is_instance_valid(city) \
			and (city as Node).has_method("get_hospital_spawn") \
			and (city as Node).has_method("get_hospital_truck_spawn"):
		var d: Variant = (city as Node).call("get_hospital_spawn")
		var t: Variant = (city as Node).call("get_hospital_truck_spawn")
		if d is Transform3D and t is Transform3D:
			return [d, t]
	return []


func _spawn_transform() -> Transform3D:
	var city: Variant = main_ref.get("city")
	if city is Node and is_instance_valid(city) and (city as Node).has_method("get_spawn_point"):
		var got: Variant = (city as Node).call("get_spawn_point")
		if got is Transform3D:
			return got
	var st: Variant = main_ref.get("spawn_transform")
	return st if st is Transform3D else Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))


# ============================== UI ===========================================
## Full-screen death card, layer 30 (over every HUD layer): dark vignette +
## huge condolences. No custom font assets exist in-project, so "serif-ish"
## is played by the default font at funeral-announcement size.
func _build_death_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	_ui.visible = false
	add_child(_ui)
	_card_root = Control.new()
	_card_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_card_root)
	var vignette := ColorRect.new()
	vignette.color = VIGNETTE_COLOR
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_root.add_child(vignette)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_root.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	center.add_child(vbox)
	var title := Label.new()
	_card_title = title
	title.text = "BLESS YOUR HEART."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DEATH_FONT_SIZE)
	title.add_theme_color_override("font_color", DEATH_TEXT_COLOR)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	vbox.add_child(title)
	var sub := Label.new()
	_card_sub = sub
	sub.text = "COUNTY GENERAL patched you up — $%d. The wrecker's out front." % HOSPITAL_FEE
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", DEATH_SUB_FONT_SIZE)
	sub.add_theme_color_override("font_color", Color(0.75, 0.68, 0.55))
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	vbox.add_child(sub)


# ============================== PLUMBING =====================================
func _on_foot() -> bool:
	return main_ref != null and main_ref.get("on_foot") == true


func _vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	return v if v is RigidBody3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


## The rig you own (the wrecker), regardless of what you are currently driving.
func _own_vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("own_vehicle") if main_ref != null else null
	return v if v is RigidBody3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


func _character() -> CharacterBody3D:
	var c: Variant = main_ref.get("character") if main_ref != null else null
	return c if c is CharacterBody3D and is_instance_valid(c) \
		and (c as Node).is_inside_tree() else null


func _point_camera(node: Node) -> void:
	var cam: Variant = main_ref.get("camera")
	if cam is Object and is_instance_valid(cam) and "target" in (cam as Object):
		(cam as Object).set("target", node)


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null
