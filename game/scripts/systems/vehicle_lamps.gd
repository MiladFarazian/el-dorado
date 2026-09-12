extends Node
## VEHICLE LAMPS — the player's ride answers the pedals (D-056; bar §4 "every verb
## has feedback"). The body builder shares ONE emissive material per lamp key
## across the whole fleet (vehicle_body_builder._emis caches by key), so a brake
## light driven on the shared material would light every tail lamp in the city.
## This system gives the PLAYER'S vehicle its own copies of "taillight" and
## "headlight" and drives them: brake or handbrake → tail lamps flare, reverse →
## they go white, night → headlamps burn and two shadowless spots throw light down
## the road. Ambient traffic is untouched (D-045 stays open — a MultiMesh problem).

const VBB := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const GLOW := preload("res://scripts/systems/streetlight_glow.gd")
const TAIL_IDLE := 1.5                # the builder's own energy (idle tail lamps)
const TAIL_BRAKE := 6.5
const TAIL_REVERSE := 3.5
const TAIL_COLOR := Color(0.85, 0.09, 0.07)
const REVERSE_COLOR := Color(1.0, 0.93, 0.82)
const HEAD_IDLE := 1.8
const HEAD_NIGHT := 5.0
const SPOT_ENERGY := 7.0
const SPOT_RANGE := 42.0
const SPOT_ANGLE := 27.0
const SPOT_ATTEN := 1.4
const SPOT_COLOR := Color(1.0, 0.95, 0.85)
const SPOT_DOWN_DEG := 4.0            # aimed at the road, not the sky
const BRAKE_MIN_SPEED := 0.6          # m/s: below this, S is not "braking"
const LERP_K := 18.0

var main_ref: Node = null
var _veh: Node3D = null
var _tail: StandardMaterial3D = null
var _head: StandardMaterial3D = null
var _spots: Array[SpotLight3D] = []
var _tail_e := TAIL_IDLE
var _head_e := HEAD_IDLE
var _white := 0.0                     # 0 red .. 1 reverse white (eased)


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		return
	on_vehicle_changed(main.get("vehicle"))


func on_vehicle_changed(v: Variant) -> void:
	for s in _spots:
		if is_instance_valid(s):
			s.queue_free()
	_spots.clear()
	_veh = null
	_tail = null
	_head = null
	if not (v is Node3D) or not is_instance_valid(v) or not (v as Node).is_inside_tree():
		return
	_veh = v
	var root: Variant = _veh.get("_visual_root")
	if not (root is Node):
		return
	var head_pos: Array[Vector3] = []
	_rebind(root as Node, VBB._mats.get("taillight"), VBB._mats.get("headlight"), head_pos)
	_make_spots(head_pos)


## Walk the visual tree; every lamp mesh wearing the fleet's shared material gets
## this vehicle's private copy instead. Head lamp positions are collected for the spots.
func _rebind(node: Node, shared_tail: Variant, shared_head: Variant, head_pos: Array[Vector3]) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if shared_tail != null and mi.material_override == shared_tail:
				if _tail == null:
					_tail = (shared_tail as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.material_override = _tail
			elif shared_head != null and mi.material_override == shared_head:
				if _head == null:
					_head = (shared_head as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.material_override = _head
				head_pos.append(_veh.to_local(mi.global_position))
		_rebind(c, shared_tail, shared_head, head_pos)


## One spot per side, at the mean of that side's head lamp positions.
func _make_spots(head_pos: Array[Vector3]) -> void:
	if head_pos.is_empty():
		return
	for side in [-1.0, 1.0]:
		var sum := Vector3.ZERO
		var n := 0
		for p in head_pos:
			if signf(p.x) == side or absf(p.x) < 0.05:
				sum += p
				n += 1
		if n == 0:
			continue
		var s := SpotLight3D.new()
		s.position = sum / float(n) + Vector3(0.0, 0.0, -0.20)
		s.rotation.x = deg_to_rad(-SPOT_DOWN_DEG)
		s.light_color = SPOT_COLOR
		s.light_energy = 0.0
		s.spot_range = SPOT_RANGE
		s.spot_angle = SPOT_ANGLE
		s.spot_attenuation = SPOT_ATTEN
		s.shadow_enabled = false            # shadow policy (D-028): a headlamp is not a caster
		s.visible = false
		_veh.add_child(s)
		_spots.append(s)


func _physics_process(delta: float) -> void:
	if _veh == null or not is_instance_valid(_veh) or not (_veh is RigidBody3D):
		return
	var driving: bool = main_ref.get("on_foot") != true and _veh.get("player_controlled") == true
	var v := (_veh as RigidBody3D).linear_velocity.dot(-_veh.global_transform.basis.z)
	var braking: bool = driving and v > BRAKE_MIN_SPEED and InputMap.has_action("brake_reverse") \
		and Input.is_action_pressed("brake_reverse")
	var handbrake: bool = driving and absf(v) > BRAKE_MIN_SPEED and InputMap.has_action("handbrake") \
		and Input.is_action_pressed("handbrake")
	var reversing := v < -BRAKE_MIN_SPEED
	var tail_target := TAIL_BRAKE if (braking or handbrake) else (TAIL_REVERSE if reversing else TAIL_IDLE)
	var night := _night()
	var k := 1.0 - exp(-LERP_K * delta)
	_tail_e = lerpf(_tail_e, tail_target, k)
	_head_e = lerpf(_head_e, lerpf(HEAD_IDLE, HEAD_NIGHT, night), k)
	_white = lerpf(_white, 1.0 if (reversing and not braking) else 0.0, k)
	if _tail != null:
		_tail.emission_energy_multiplier = _tail_e
		_tail.emission = TAIL_COLOR.lerp(REVERSE_COLOR, _white)
		_tail.albedo_color = _tail.emission
	if _head != null:
		_head.emission_energy_multiplier = _head_e
	for s in _spots:
		if is_instance_valid(s):
			s.light_energy = SPOT_ENERGY * night
			s.visible = night > 0.02


func _night() -> float:
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary) or not (sys as Dictionary).has("sky_weather"):
		return 0.0
	var sky: Variant = (sys as Dictionary)["sky_weather"]
	if not (sky is Node):
		return 0.0
	var t: Variant = (sky as Node).get("time_of_day")
	return GLOW.level_for_hour(t as float) if t is float else 0.0
