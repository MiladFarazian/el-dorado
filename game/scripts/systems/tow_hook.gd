extends Node
## THE HOOK — the protagonist's signature verb. Press F near a "towable"
## RigidBody3D to chain it to the wrecker's rear; press F again to release.
## Joint choice: ONE Generic6DOFJoint3D placed at the midpoint between the two
## anchors, linear limits ±CHAIN_SLACK per axis, all angular limits disabled.
## That reads as a chain: slack inside the limit box, taut at the edge, target
## free to swing/yaw/roll on corners and ramps. No intermediate hitch body —
## a light body between a 2400 kg truck and a 1200 kg junker is the classic
## jitter source at 60 Hz. A taut-only radial damper kills orbit-slingshot.

# ============================== TUNABLES =====================================
const HOOK_RANGE := 6.0            # max origin distance from rear anchor (m)
const SNAP_DISTANCE := 9.0         # anchors past this -> chain breaks (m)
const PLAYER_HALF_LENGTH := 2.6    # rear anchor = origin + basis.z * this (m)
const TARGET_HALF_LENGTH := 1.8    # towed body's end-offset guess (m)
const CHAIN_SLACK := 1.3           # per-axis linear play in the joint (m)
const LIMIT_SOFTNESS := 0.8        # 6DOF linear limit softness (higher=softer)
const LIMIT_RESTITUTION := 0.05    # near-zero: no bounce when chain goes taut
const LIMIT_DAMPING := 1.0         # 6DOF linear limit damping
const KEEP_BODY_COLLISION := true  # truck and towed body still bump each other
const ASSIST_DAMPING := 900.0      # N*s/m radial damper once past taut length
const ASSIST_MAX_FORCE := 6000.0   # cap on the assist damper force (N)
const CABLE_THICKNESS := 0.06      # visible cable cross-section (m)
const CABLE_COLOR := Color(0.82, 0.68, 0.24)
const SNAP_FLASH_TIME := 1.2       # seconds the "SNAPPED" flash stays up
const HINT_FONT_SIZE := 20
const SNAP_FONT_SIZE := 42

# ============================== PUBLIC API ===================================
signal hooked(body: RigidBody3D)
signal released(body: RigidBody3D)

var hooked_body: RigidBody3D = null

# ============================== STATE ========================================
var main_ref: Node = null
var _joint: Generic6DOFJoint3D = null
var _target_anchor_local := Vector3.ZERO   # hooked end, in target local space
var _taut_length := 0.0                    # hook-time distance + slack (m)
var _cable: MeshInstance3D = null
var _ui: CanvasLayer = null
var _hint_label: Label = null
var _snap_label: Label = null
var _snap_timer := 0.0


func setup(main: Node) -> void:
	main_ref = main
	_build_cable()
	if not bool(main.get("smoke_mode")):
		_build_ui()


func on_vehicle_changed(_vehicle: Node) -> void:
	# The joint references the OLD body; drop everything before it is freed.
	if hooked_body != null or _joint != null:
		_release()


func _physics_process(_delta: float) -> void:
	if main_ref == null:
		return
	var player := _player()
	# F is a driving verb: on foot it must neither release an active tow nor
	# hook things to a truck nobody is driving. Chain maintenance still runs.
	var on_foot: bool = main_ref.get("on_foot") == true
	if not on_foot and player != null and InputMap.has_action("hook") \
			and Input.is_action_just_pressed("hook"):
		if hooked_body != null:
			_release()   # always releasable, boom or not: never strand a chain
		elif _has_boom(player):
			_try_hook(player)
	if hooked_body != null:
		if player == null or not is_instance_valid(hooked_body) \
				or not hooked_body.is_inside_tree():
			_release()   # towed body freed externally, or player swapped
		else:
			var a := _rear_anchor(player)
			var b := hooked_body.to_global(_target_anchor_local)
			var dist := a.distance_to(b)
			if dist > SNAP_DISTANCE and not _chain_held():
				_release()
				_flash_snapped()
			else:
				_apply_taut_damping(player, a, b, dist)
	_update_cable(player)


func _process(delta: float) -> void:
	if _snap_label != null and is_instance_valid(_snap_label) and _snap_timer > 0.0:
		_snap_timer -= delta
		_snap_label.modulate.a = clampf(_snap_timer / (SNAP_FLASH_TIME * 0.5), 0.0, 1.0)
		if _snap_timer <= 0.0:
			_snap_label.visible = false
	if _hint_label == null or not is_instance_valid(_hint_label):
		return
	if main_ref != null and main_ref.get("on_foot") == true:
		_hint_label.visible = false  # the hook prompt is a driving prompt
		return
	var player := _player()
	if player != null and hooked_body != null and is_instance_valid(hooked_body):
		var d := _rear_anchor(player).distance_to(hooked_body.to_global(_target_anchor_local))
		_hint_label.text = "F — RELEASE   chain %.1f m" % d
		_hint_label.visible = true
	elif player != null and _nearest_towable(player) != null:
		_hint_label.text = "F — HOOK" if _has_boom(player) \
			else "NO BOOM — THE WRECKER DOES THAT"
		_hint_label.visible = true
	else:
		_hint_label.visible = false


# ============================== HOOK / RELEASE ===============================
func _player() -> RigidBody3D:
	if main_ref == null:
		return null
	var v: Variant = main_ref.get("vehicle")
	if is_instance_valid(v) and v is RigidBody3D and (v as Node).is_inside_tree():
		return v as RigidBody3D
	return null


## The Hook is equipment, not a superpower: only a profile that declares
## "tow_boom" can pick anything up. Jack a sedan and you are a guy in a sedan.
## A body that is not a profile vehicle at all keeps the old permissive
## behaviour rather than silently losing the game's core verb.
func _has_boom(veh: RigidBody3D) -> bool:
	if veh == null or not is_instance_valid(veh):
		return false
	if not veh.has_method("has_boom"):
		return true
	return bool(veh.call("has_boom"))


func _rear_anchor(veh: RigidBody3D) -> Vector3:
	return veh.global_position + veh.global_transform.basis.z * PLAYER_HALF_LENGTH


func _nearest_towable(player: RigidBody3D) -> RigidBody3D:
	var anchor := _rear_anchor(player)
	var best: RigidBody3D = null
	var best_d := HOOK_RANGE
	for n: Node in get_tree().get_nodes_in_group("towable"):
		if n == player or not is_instance_valid(n) or not (n is RigidBody3D):
			continue
		var body := n as RigidBody3D
		if not body.is_inside_tree():
			continue
		var d := anchor.distance_to(body.global_position)
		if d <= best_d:
			best_d = d
			best = body
	return best


func _try_hook(player: RigidBody3D) -> void:
	var target := _nearest_towable(player)
	if target == null:
		return
	var rear := _rear_anchor(player)
	var near_end := Vector3(0, 0, -TARGET_HALF_LENGTH)
	var far_end := Vector3(0, 0, TARGET_HALF_LENGTH)
	_target_anchor_local = near_end \
		if target.to_global(near_end).distance_to(rear) \
			<= target.to_global(far_end).distance_to(rear) else far_end
	var target_anchor := target.to_global(_target_anchor_local)
	_taut_length = rear.distance_to(target_anchor) + CHAIN_SLACK

	var joint := Generic6DOFJoint3D.new()
	joint.name = "TowChainJoint"
	joint.exclude_nodes_from_collision = not KEEP_BODY_COLLISION
	add_child(joint)
	joint.global_transform = Transform3D(Basis.IDENTITY, (rear + target_anchor) * 0.5)
	var params: Array[Callable] = [joint.set_param_x, joint.set_param_y, joint.set_param_z]
	var flags: Array[Callable] = [joint.set_flag_x, joint.set_flag_y, joint.set_flag_z]
	for i in 3:
		flags[i].call(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		flags[i].call(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		params[i].call(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -CHAIN_SLACK)
		params[i].call(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, CHAIN_SLACK)
		params[i].call(Generic6DOFJoint3D.PARAM_LINEAR_LIMIT_SOFTNESS, LIMIT_SOFTNESS)
		params[i].call(Generic6DOFJoint3D.PARAM_LINEAR_RESTITUTION, LIMIT_RESTITUTION)
		params[i].call(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, LIMIT_DAMPING)
	joint.node_a = player.get_path()
	joint.node_b = target.get_path()
	_joint = joint
	hooked_body = target

	if target.is_in_group("police"):
		var systems: Variant = main_ref.get("systems")
		if systems is Dictionary:
			var pol: Variant = (systems as Dictionary).get("police")
			if is_instance_valid(pol) and (pol as Object).has_method("add_heat"):
				pol.call("add_heat", 2, "HOOKED A CRUISER")
	hooked.emit(target)


func _release() -> void:
	var body := hooked_body
	hooked_body = null
	_taut_length = 0.0
	if _joint != null:
		if is_instance_valid(_joint):
			_joint.node_a = NodePath()
			_joint.node_b = NodePath()
			_joint.queue_free()
		_joint = null
	if _cable != null and is_instance_valid(_cable):
		_cable.visible = false
	if body != null and not is_instance_valid(body):
		body = null
	released.emit(body)


## Chain only pulls: once anchors are past the taut length, bleed off the
## separating radial velocity so high-speed corners don't orbit-slingshot.
func _apply_taut_damping(player: RigidBody3D, a: Vector3, b: Vector3, dist: float) -> void:
	if dist <= _taut_length or dist < 0.001:
		return
	var dir := (b - a) / dist
	var vrel := (hooked_body.linear_velocity - player.linear_velocity).dot(dir)
	if vrel <= 0.0:
		return
	var f := minf(vrel * ASSIST_DAMPING, ASSIST_MAX_FORCE)
	hooked_body.apply_central_force(-dir * f)
	player.apply_central_force(dir * f * 0.5)


# ============================== CABLE VISUAL =================================
func _build_cable() -> void:
	_cable = MeshInstance3D.new()
	_cable.name = "TowCable"
	var bm := BoxMesh.new()
	bm.size = Vector3(CABLE_THICKNESS, CABLE_THICKNESS, 1.0)
	_cable.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CABLE_COLOR
	mat.roughness = 0.6
	_cable.material_override = mat
	_cable.visible = false
	add_child(_cable)   # Node3D under a plain Node: transform acts as global


func _update_cable(player: RigidBody3D) -> void:
	if _cable == null or not is_instance_valid(_cable):
		return
	if player == null or hooked_body == null or not is_instance_valid(hooked_body):
		_cable.visible = false
		return
	var a := _rear_anchor(player)
	var b := hooked_body.to_global(_target_anchor_local)
	var d := a.distance_to(b)
	if d < 0.05:
		_cable.visible = false
		return
	var dir := (b - a) / d
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, d))
	_cable.global_transform = Transform3D(basis, (a + b) * 0.5)
	_cable.visible = true


# ============================== UI ===========================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_hint_label = Label.new()
	_hint_label.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 56)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint_label.visible = false
	_ui.add_child(_hint_label)
	_snap_label = Label.new()
	_snap_label.text = "SNAPPED"
	_snap_label.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_snap_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_snap_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_snap_label.add_theme_font_size_override("font_size", SNAP_FONT_SIZE)
	_snap_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	_snap_label.add_theme_constant_override("outline_size", 8)
	_snap_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_snap_label.visible = false
	_ui.add_child(_snap_label)


## THE FULL EIGHT: while Book is holding on, the chain holds too (data:
## full_eight.json "chain_unbreakable"). The joint still limits; only the snap is refused.
func _chain_held() -> bool:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if not (sys is Dictionary) or not (sys as Dictionary).has("full_eight"):
		return false
	var fe: Variant = (sys as Dictionary)["full_eight"]
	return fe is Node and (fe as Node).get("chain_held") == true


func _flash_snapped() -> void:
	if _snap_label == null or not is_instance_valid(_snap_label):
		return
	_snap_timer = SNAP_FLASH_TIME
	_snap_label.modulate.a = 1.0
	_snap_label.visible = true
