class_name RaycastVehicle
extends RigidBody3D
## Custom raycast-suspension vehicle controller — the physics heart of the game.
## Per-wheel spring/damper suspension, friction-circle tire forces, speed-
## sensitive steering, handbrake slides. All tuning lives in a JSON profile
## under res://data/vehicles/ so feel can be iterated (and hot-reloaded with T)
## without touching code. See docs/tech/physics/tuning-guide.md.

signal profile_reloaded(display_name: String)

@export var profile_path: String = "res://data/vehicles/wrecker.json"

var p: Dictionary = {}
var display_name := "Unnamed"
var wheels: Array[Dictionary] = []
var current_steer := 0.0
# World systems (weather) scale tire grip here: 1.0 dry, ~0.72 storm-wet.
var grip_modifier := 1.0
var grip_bonus := 1.0      # THE FULL EIGHT multiplies the friction circle; weather owns grip_modifier
# Damage systems (police gunfire) scale drive force here: 1.0 healthy,
# sputtering below half hull, 0.0 engine dead. Brakes and steering are never
# touched — a shot-dead car still stops and still points, it just won't GO.
var power_modifier := 1.0
# False while the player is on foot: the parked rig ignores the keyboard.
var player_controlled := true

# External input (smoke test / future AI drivers) overrides the keyboard.
var external_input := false
var ext_throttle := 0.0
var ext_brake := 0.0
var ext_steer := 0.0
var ext_handbrake := false

var _visual_root: Node3D
var _just_reset := false
var _dish_mat: StandardMaterial3D = null


func _ready() -> void:
	can_sleep = false
	continuous_cd = true
	# Every profile-driven vehicle is takeable in principle; carjack.gd scans
	# this group to find what the player can get into.
	add_to_group("drivable")
	_load_profile()
	_rebuild()


func set_external_input(throttle: float, brake: float, steer: float, hb: bool) -> void:
	external_input = true
	ext_throttle = throttle
	ext_brake = brake
	ext_steer = steer
	ext_handbrake = hb


## Hand the controls back to the keyboard. A stolen cruiser was being driven by
## police.gd through set_external_input and would otherwise ignore the player
## forever; the stale inputs are cleared too, so nothing is left held down.
func clear_external_input() -> void:
	external_input = false
	ext_throttle = 0.0
	ext_brake = 0.0
	ext_steer = 0.0
	ext_handbrake = false


## Does this vehicle carry the wrecker boom? Data-driven ("tow_boom" in the
## profile) so the Hook rides with the truck instead of with whatever the player
## happens to be sitting in.
func has_boom() -> bool:
	return bool(p.get("tow_boom", false))


func reload_profile() -> void:
	_load_profile()
	_rebuild()
	profile_reloaded.emit(display_name)


# Physics frame of the last reset_to teleport — consumers (vehicle_audio's
# impact watcher) use it to tell an R-reset from a real crash.
var last_reset_frame := -1


func reset_to(t: Transform3D) -> void:
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	current_steer = 0.0
	last_reset_frame = int(Engine.get_physics_frames())
	for w in wheels:
		w["compression"] = 0.0
	_just_reset = true


func _load_profile() -> void:
	var parsed: Variant = null
	var f := FileAccess.open(profile_path, FileAccess.READ)
	if f == null:
		push_error("RaycastVehicle: cannot open profile: " + profile_path)
	else:
		parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("RaycastVehicle: invalid JSON in: " + profile_path)
			parsed = null
	if parsed != null:
		p = parsed
	elif p.is_empty():
		# Corrupt/missing first load: fall back to code defaults so the car
		# still gets collision and stays drivable (a failed reload keeps the
		# previous profile instead).
		p = {"name": "PROFILE ERROR"}
	display_name = str(p.get("name", "Unnamed"))
	mass = _f("mass", 1500.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, _f("com_height", -0.3), -_f("com_forward", 0.0))
	linear_damp = 0.0
	angular_damp = _f("angular_damp", 0.5)


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	wheels.clear()
	if p.is_empty():
		return

	var body_size := _vec3(p.get("body_size", [2.0, 1.4, 4.5]))

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size
	col.shape = box
	add_child(col)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	var wb_f := _f("wheelbase_front", 1.4)
	var wb_r := _f("wheelbase_rear", 1.4)
	var half_track := _f("track_width", 1.7) * 0.5
	var hard_y := _f("hardpoint_height", -0.3)
	var radius := _f("wheel_radius", 0.38)
	var width := _f("wheel_width", 0.28)
	var drive := str(p.get("drive", "rear"))

	# M9: the single greybox slab became a styled silhouette (body_style in the
	# JSON profile). Deterministic, visual-only — the collision box above is
	# byte-for-byte the M1 physics. M16 hands the builder the REAL wheel
	# stations so the arches land on the tires, plus the hero flag (interiors,
	# badges, plate text) that ambient traffic shells do not pay for.
	# STATIC RIDE HEIGHT, PER AXLE. The body builder traces its wheel arches on
	# these numbers, so an even quarter-mass split is not good enough: com_forward
	# puts more of the car on one axle and the two hubs settle at DIFFERENT
	# heights. Measured in-engine on a settled car against the even split the
	# builder used to be handed, the wheels missed the arches drawn for them by
	# +37.6/-37.7 mm (Vantage), +42.3/-42.5 (Brisket), +20.0/-20.3 (Slab) — on a
	# bar row whose whole width is 45 mm. The front arch was closing on the tyre
	# while the rear yawned, on the same car.
	# Moment balance about the CoM (z_com = -com_forward, front hub at -wb_f):
	#   c_f (wb_f - a) = c_r (wb_r + a)   and   2k (c_f + c_r) = m g
	#
	# `a` IS NOT com_forward — IT IS TWICE IT, and that is not a fudge. The pitch
	# lever this solver actually uses is the one it hands to `apply_force` below:
	#   apply_force(up * spring_force, hard_global - com_global)
	# Godot's `position` argument is an offset from the body ORIGIN and the engine
	# subtracts the centre of mass itself, so passing an offset that has already
	# had the CoM taken out subtracts it TWICE — every force in this file swings
	# on `hard - 2*com`, not `hard - com`. Predicted front-axle share against the
	# settled car, five profiles, single vs double lever:
	#   Vantage 0.6138 / 0.7172 (measured 0.7175)   Interceptor 0.4885 / 0.4689 (0.4689)
	#   Brisket 0.5778 / 0.6333 (0.6335)            Wrecker 0.5676 / 0.6081 (0.6081)
	#   Slab    0.5434 / 0.5723 (0.5722)
	# Five for five on the doubled lever. The arches are drawn on the ride height
	# the car REALLY settles at, so this mirrors the solver as it is, exactly the
	# way JUNKER_W mirrors repo_board. **If `force_pos` is ever corrected, this
	# factor of 2 must go in the SAME edit** — and note that correcting it changes
	# the wrecker's motion, which is the frozen smoke baseline (see wrecker.json).
	var rest := _f("suspension_rest", 0.4)
	var wb_sum := maxf(wb_f + wb_r, 0.001)
	var front_share := clampf((wb_r + 2.0 * _f("com_forward", 0.0)) / wb_sum, 0.05, 0.95)
	var comp_sum := mass * 9.81 / maxf(2.0 * _f("spring_rate", 45000.0), 1.0)
	var comp_f := clampf(comp_sum * front_share, 0.0, rest)
	var comp_r := clampf(comp_sum * (1.0 - front_share), 0.0, rest)
	const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
	BODY_BUILDER.build(_visual_root, str(p.get("body_style", "box")), body_size,
		_color(p.get("color", [0.8, 0.2, 0.2])), str(p.get("door_text", "")), {
			"hero": true,
			"badge": display_name,
			"plate": str(p.get("plate_text", "")),
			"wheel_z": Vector2(-wb_f, wb_r),
			"wheel_r": radius,
			# Per-station, front then rear (see comp_f/comp_r above).
			"wheel_y": Vector2(hard_y - (rest - comp_f), hard_y - (rest - comp_r)),
			# M19: the builder needs the TRACK and the TREAD WIDTH too — its
			# fender blister has to reach the tyre's outer face, and it was
			# measured standing 23-142 mm short of it on every hero profile.
			"wheel_x": half_track,
			"wheel_w": width,
		})
	var layout: Array[Dictionary] = [
		{"pos": Vector3(-half_track, hard_y, -wb_f), "steers": true, "rear": false},
		{"pos": Vector3(half_track, hard_y, -wb_f), "steers": true, "rear": false},
		{"pos": Vector3(-half_track, hard_y, wb_r), "steers": false, "rear": true},
		{"pos": Vector3(half_track, hard_y, wb_r), "steers": false, "rear": true},
	]
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.07, 0.07, 0.08)
	wheel_mat.roughness = 0.95
	# M10: rims. A contrasting disc inset on each outer face turns a black
	# cylinder into a wheel — profile-driven so the Slab can run gold.
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = _color(p.get("rim_color", [0.72, 0.73, 0.76]))
	# 0.85 metallic with no reflection probe in the scene renders a rim as a
	# near-black mirror of nothing. Mostly-diffuse metal reads as metal.
	# D-068, second half: a wheel is ALWAYS inside the fender's own shadow, so
	# sky ambient is the only light it ever gets — and metallic scales diffuse by
	# (1 - metallic) while the specular it buys instead needs a reflection this
	# scene has no probe to supply. At 0.55 the rim threw away more than half of
	# its only light source. 0.35 keeps the metal read and returns 36% of it.
	rim_mat.metallic = 0.35
	rim_mat.roughness = 0.30
	# M16: rim_style is a VISUAL profile field — a fleet sedan runs plain
	# steelies, a slab runs wires over whitewalls, a lifted truck runs dark
	# alloys. Wheel geometry (radius/width/position) is untouched physics.
	var rim_style := str(p.get("rim_style", "spoke"))
	# The wheel's inner dish: darker than the rim and never metallic, so the
	# bright flange in front of it reads as a rim with depth behind it.
	_dish_mat = StandardMaterial3D.new()
	_dish_mat.albedo_color = rim_mat.albedo_color * (0.55 if rim_style == "steelie" else 0.42)
	_dish_mat.roughness = 0.75
	var white_mat: StandardMaterial3D = null
	if bool(p.get("whitewall", false)):
		white_mat = StandardMaterial3D.new()
		white_mat.albedo_color = Color(0.86, 0.85, 0.80)
		white_mat.roughness = 0.65
	for w in layout:
		var drives: bool = (drive == "all") \
			or (drive == "rear" and w["rear"]) \
			or (drive == "front" and not w["rear"])
		var pivot := Node3D.new()
		pivot.position = w["pos"]
		_visual_root.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		# THE TYRE. It used to be two CylinderMeshes — and a cylinder has a flat
		# CAP, a black disc of full sidewall radius sitting at the wheel's outer
		# face. That cap is why every rim behind it had to be stacked PROUD of the
		# tyre to be seen at all, which is what turned the rim into a fan of loose
		# plates floating in front of the wheel. The tyre is now a lathed
		# cross-section with a real bead, so its centre is OPEN and the rim can sit
		# where a rim sits: inside the tyre, with depth behind it.
		var tyre := MeshInstance3D.new()
		tyre.mesh = _tyre_mesh(radius, width)
		tyre.set_surface_override_material(0, wheel_mat)
		tyre.set_surface_override_material(1, white_mat if white_mat != null else wheel_mat)
		spin.add_child(tyre)
		# THE RIM (D-017). What shipped before was a pile of loose primitives:
		# four full-diameter bars, a flat dish disc, and FOURTEEN chord boxes ringed
		# at 0.635 R with `seg.rotation.x = -a`. That sign is the whole bug — a
		# chord at angle `a` is tangent when the box is rolled by +a; at -a the
		# chord is mirrored about the vertical, so it lies tangent at 0 and 90 deg
		# and stands fully RADIAL at 45 deg. That is QA's "ring of irregular tan
		# wedges that do not converge on the hub, several visibly detached": a
		# broken fan, on every wheel of every car, and all three rim_styles carried
		# it because all three shared the loop.
		# It is now ONE cached mesh: a lathed flange that closes on itself, a
		# recessed bowl behind it, a raised centre cap, and spokes emitted into the
		# same surface as tapered blades that physically reach the hub. Per wheel:
		# 21 nodes became 3, and nothing can detach because nothing is loose.
		var out_sign: float = signf(float(w["pos"].x))
		var face: float = width * 0.5             # the tyre's own outer face
		var rim := MeshInstance3D.new()
		rim.mesh = _wheel_face(radius, width, rim_style)
		rim.set_surface_override_material(0, rim_mat)
		rim.set_surface_override_material(1, _dish_mat)
		# Built for the +X flank; the far side is a 180 deg turn about Y, which
		# mirrors it WITHOUT flipping the winding (a negative scale would).
		if out_sign < 0.0:
			rim.rotation.y = PI
		spin.add_child(rim)
		wheels.append({
			"local_pos": w["pos"],
			"steers": w["steers"],
			"drives": drives,
			"rear": w["rear"],
			"pivot": pivot,
			"spin": spin,
			"compression": 0.0,
			"grounded": false,
			# M23 tire_fx read-outs (written every physics tick, never read here):
			"contact": Vector3.ZERO, "normal": Vector3.UP,
			"lat_slip": 0.0, "slide": 0.0, "fwd_speed": 0.0,
		})
	# Fresh wheels have compression 0: skip the damper for one frame so a
	# tuning hot-reload at speed doesn't inject a fake compression velocity.
	_just_reset = true


func _physics_process(delta: float) -> void:
	if p.is_empty() or wheels.is_empty():
		return

	var throttle := 0.0
	var brake := 0.0
	var steer_axis := 0.0
	var handbrake := false
	if external_input:
		throttle = ext_throttle
		brake = ext_brake
		steer_axis = ext_steer
		handbrake = ext_handbrake
	elif player_controlled and InputMap.has_action("accelerate"):
		throttle = Input.get_action_strength("accelerate")
		brake = Input.get_action_strength("brake_reverse")
		steer_axis = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("handbrake")

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(-global_transform.basis.z)

	var max_steer := deg_to_rad(_f("max_steer_deg", 32.0)) / (1.0 + speed * _f("steer_falloff", 0.03))
	current_steer = move_toward(current_steer, steer_axis * max_steer, _f("steer_speed", 4.0) * delta)

	var space := get_world_3d().direct_space_state
	var rest := _f("suspension_rest", 0.4)
	var radius := _f("wheel_radius", 0.38)
	var ray_len := rest + radius
	var up := global_transform.basis.y
	var com_global := to_global(center_of_mass)
	var n_drive := 0
	for w in wheels:
		if w["drives"]:
			n_drive += 1
	n_drive = maxi(n_drive, 1)
	var n_grounded := 0

	var engine_force := _f("max_engine_force", 9000.0) * power_modifier \
		* clampf(1.0 - forward_speed / _f("top_speed", 40.0), 0.0, 1.0)

	for w in wheels:
		var hard_global: Vector3 = to_global(w["local_pos"])
		var query := PhysicsRayQueryParameters3D.create(hard_global, hard_global - up * ray_len)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		var pivot: Node3D = w["pivot"]

		if hit.is_empty():
			w["grounded"] = false
			w["compression"] = 0.0
			pivot.position = Vector3(w["local_pos"].x, w["local_pos"].y - rest, w["local_pos"].z)
			if w["steers"]:
				pivot.rotation.y = current_steer
			continue

		var hit_d: float = hard_global.distance_to(hit["position"])
		var compression := clampf(ray_len - hit_d, 0.0, rest)
		var comp_vel := 0.0 if _just_reset else (compression - float(w["compression"])) / delta
		w["compression"] = compression
		w["grounded"] = true
		n_grounded += 1

		# Suspension: spring + damper along body up, applied at the hardpoint.
		var spring_force := _f("spring_rate", 45000.0) * compression + _f("damping", 4500.0) * comp_vel
		spring_force = maxf(spring_force, 0.0)
		apply_force(up * spring_force, hard_global - com_global)

		# Wheel frame (steered for the front axle).
		var b := global_transform.basis
		var wheel_forward: Vector3 = -b.z
		var wheel_right: Vector3 = b.x
		if w["steers"]:
			wheel_forward = wheel_forward.rotated(up, current_steer)
			wheel_right = wheel_right.rotated(up, current_steer)

		var contact: Vector3 = hit["position"]
		var at_hub: bool = bool(p.get("apply_forces_at_hub", true))
		var force_pos: Vector3 = (hard_global if at_hub else contact) - com_global

		var point_vel: Vector3 = linear_velocity + angular_velocity.cross(force_pos)
		var lat_speed := point_vel.dot(wheel_right)
		var fwd_speed := point_vel.dot(wheel_forward)
		w["contact"] = hit["position"]
		w["normal"] = hit.get("normal", Vector3.UP)
		w["lat_slip"] = lat_speed
		w["fwd_speed"] = fwd_speed

		# Friction circle budget scales with suspension load (and weather).
		var max_grip := _f("tire_friction", 1.2) * spring_force * grip_modifier * grip_bonus

		var lat_stiff := _f("lateral_stiffness", 8000.0)
		if handbrake and w["rear"]:
			lat_stiff *= _f("handbrake_grip_mult", 0.3)
		var lat_force := -lat_speed * lat_stiff

		var long_force := 0.0
		if w["drives"] and throttle > 0.0:
			long_force += engine_force * throttle / float(n_drive)
		if brake > 0.0:
			if forward_speed > 0.5:
				long_force += -_f("brake_force", 15000.0) * brake * 0.25
			elif w["drives"]:
				# Reverse tapers to zero at reverse_top_speed (forward_speed < 0 here).
				var rev_scale := clampf(1.0 + forward_speed / _f("reverse_top_speed", 12.0), 0.0, 1.0)
				long_force += -_f("reverse_force", 5000.0) * power_modifier \
					* brake * rev_scale / float(n_drive)
		if handbrake and w["rear"]:
			long_force += clampf(-fwd_speed * 3000.0, -max_grip, max_grip)

		# True friction circle: lateral and longitudinal share one grip budget.
		var tire := wheel_right * lat_force + wheel_forward * long_force
		var tire_mag := tire.length()
		w["slide"] = tire_mag / maxf(max_grip, 1.0)   # >= 1.0: the friction circle is saturated
		if tire_mag > max_grip:
			tire *= max_grip / tire_mag
		apply_force(tire, force_pos)

	_just_reset = false

	# Aero + rolling resistance. Rolling resistance used to start at 0.5 m/s and
	# nothing below it: a creeping car accelerated to exactly 0.5 and stayed there.
	# It now fades in from rest, so a creep is damped from its first centimetre.
	if speed > 0.02:
		var resist := _f("drag", 0.5) * speed * speed \
			+ _f("rolling_resistance", 150.0) * clampf(speed / 0.5, 0.0, 1.0)
		apply_central_force(-linear_velocity.normalized() * resist)
	apply_central_force(-up * _f("downforce", 2.0) * speed * speed)

	# PARK HOLD (D-059; Milad: "all cars drift forward when they shouldn't").
	# The tyre model has no static friction: lateral force is slip-proportional
	# and longitudinal force is engine or brake only, so a car at rest with its
	# body pitched a degree by com_forward is pushed along its nose by its own
	# springs (they act along BODY up) and nothing answers — 3.27 m in 8 s on the
	# flat spawn street, measured. Real tyres hold that with static friction;
	# here, with no pedal down and every wheel on the ground, the horizontal
	# velocity below park_hold_speed is bled off at park_hold_decel. A shove from
	# outside (a ram, a tow) exceeds the speed and the hold lets go.
	if throttle <= 0.0 and brake <= 0.0 and n_grounded == wheels.size():
		var hv := linear_velocity - up * linear_velocity.dot(up)
		if hv.length() < _f("park_hold_speed", 0.6):
			var held := hv.move_toward(Vector3.ZERO, _f("park_hold_decel", 6.0) * delta)
			linear_velocity += held - hv

	# Visual wheel placement + spin.
	for w in wheels:
		var pivot: Node3D = w["pivot"]
		var lp: Vector3 = w["local_pos"]
		pivot.position = Vector3(lp.x, lp.y - (rest - float(w["compression"])), lp.z)
		if w["steers"]:
			pivot.rotation.y = current_steer
		var spin: Node3D = w["spin"]
		spin.rotate_x(-forward_speed / maxf(radius, 0.05) * delta)


## Per-style rim geometry: spoke count, tangential half-width of a blade at its
## rim end and at its hub end (both in wheel radii), and the centre-cap radius.
## A steelie is not spokeless — it is a solid web with six hand-holes punched in
## it, which is exactly what six FAT blades read as.
const RIM_STYLES := {
	"steelie": {"n": 6, "hw_o": 0.150, "hw_i": 0.085, "hub": 0.270},
	"alloy": {"n": 5, "hw_o": 0.100, "hw_i": 0.042, "hub": 0.170},
	"wire": {"n": 16, "hw_o": 0.022, "hw_i": 0.011, "hub": 0.130},
	"spoke": {"n": 5, "hw_o": 0.085, "hw_i": 0.038, "hub": 0.165},
}
static var _face_meshes: Dictionary = {}


## THE WHEEL FACE — one cached two-surface mesh (0 = bright rim, 1 = dark pocket).
## The lathe profile runs OUTER radius to centre, so ONE winding rule serves
## every segment: quad(P[i]@a0, P[i+1]@a0, P[i+1]@a1, P[i]@a1). Each profile
## segment gets its own smooth group, so normals merge AROUND the wheel (it
## reads round at 28 sides) but never across a profile crease (the flange keeps
## its edge). Rim-to-tyre diameter 0.665 — a real car runs 0.60-0.68.
##
## D-068 — WHY THE RIM WENT BLACK WHEN THE STARBURST DIED, and it is not colour
## and not the material. A wheel lives inside a fender opening: at noon the body
## shadows the whole of it, so EVERY rim surface is lit by sky only, and how much
## sky a surface sees is decided by the RADIAL TILT of the lathe. Measured off
## the generated normals of the old profile:
##   flange face  r 0.665->0.560 R, x +0.002 -> -0.006   DISHED, n_r = -0.20
##   bowl wall    r 0.560->0.470 R, x -0.006 -> -0.038   DISHED, n_r = -0.68
##   web rise     r 0.470->hub,     x -0.038 -> -0.022   domed,  n_r = +0.21
##   centre cap   r hub->0,         x -0.022 -> -0.012   domed,  n_r = +0.10
## A DISHED ring tilts its top edge DOWN — at the top of the wheel, the part a
## viewer actually reads, it faces the ground. The only two surfaces tilted UP
## into the sky were the web and the cap, and 43% of the disc (the web) was
## assigned to the DARK pocket material. So the bright 29% pointed at the dirt
## and the lit 43% was painted dark: mean 19.0/255, sigma 14.3, no structure.
##
## The profile below is domed where the old one was dished. The flange face
## rolls OUTBOARD as it runs inward, the web climbs to a hub boss that stands
## proud of the bead, and the centre cap domes: three bright rings whose normals
## all tilt UP at the top of the wheel and DOWN at the bottom, which is exactly
## how a real wheel reads — bright crown, dark six o'clock. The DEPTH that killed
## the starburst is unchanged and now does one job only: it is the POCKET the
## spokes bridge, 32-38 mm behind them, dark on purpose.
## Nothing here is a plate, nothing is loose: it is one closed lathe.
static func _wheel_face(radius: float, width: float, style: String) -> ArrayMesh:
	var key := "wf_%.3f_%.3f_%s" % [radius, width, style]
	if _face_meshes.has(key):
		return _face_meshes[key]
	var cfg: Dictionary = RIM_STYLES.get(style, RIM_STYLES["spoke"])
	const SEG := 28
	var face := width * 0.5
	var r_out := radius * 0.665            # the bead: where tyre hands over to rim
	var r_lip := radius * 0.610            # inner edge of the flange face
	var r_pk := radius * 0.545             # the pocket's outer wall
	var r_hub: float = radius * float(cfg["hub"])
	var r_web: float = maxf(r_hub * 1.5, radius * 0.260)   # pocket floor, inner edge
	# (radius, x-from-wheel-centre). Outer edge first, centre cap last.
	var prof: Array[Vector2] = [
		Vector2(r_out, face - 0.028),        # flange barrel, inboard end
		Vector2(r_out, face + 0.002),        # flange crest, level with the bead
		Vector2(r_lip, face + 0.008),        # flange face DOMES outboard: catches sky
		Vector2(r_pk, face - 0.030),         # pocket wall: the depth behind the face
		Vector2(r_web, face - 0.026),        # pocket floor, under the spokes
		Vector2(r_hub, face + 0.004),        # web climbs to a PROUD hub boss
		Vector2(0.0, face + 0.012),          # domed centre cap
	]
	var band := [0, 0, 1, 1, 0, 0]           # which surface each segment belongs to
	var mesh: ArrayMesh = null
	for surf in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in prof.size() - 1:
			if band[i] != surf:
				continue
			st.set_smooth_group(i + 1)
			for k in SEG:
				var a0 := TAU * float(k) / float(SEG)
				var a1 := TAU * float(k + 1) / float(SEG)
				_quad(st, _lathe(prof[i], a0), _lathe(prof[i + 1], a0),
					_lathe(prof[i + 1], a1), _lathe(prof[i], a1))
		if surf == 0:
			_spokes(st, radius, face, r_pk, r_hub, cfg)
		st.generate_normals()
		mesh = st.commit(mesh)
	_face_meshes[key] = mesh
	return mesh


## THE TYRE — a lathed cross-section: bead, sidewall bulge, rounded shoulder,
## flat tread, and an OPEN centre at the bead radius so the rim inside it reads
## with real depth. Surface 0 is rubber; surface 1 is the sidewall band the
## whitewall profiles paint (harmlessly black on everything else).
## Winding: the front normal of quad(P[i]@a0, P[i+1]@a0, P[i+1]@a1, P[i]@a1) is
## proportional to (-dr, dx), so this profile runs INBOARD bead -> tread ->
## outboard bead and every segment comes out facing away from the rubber.
static func _tyre_mesh(radius: float, width: float) -> ArrayMesh:
	var key := "ty_%.3f_%.3f" % [radius, width]
	if _face_meshes.has(key):
		return _face_meshes[key]
	const SEG := 28
	var f := width * 0.5
	var rb := radius * 0.655                   # bead: it meets the rim flange
	var prof: Array[Vector2] = [
		Vector2(rb, -f),
		Vector2(radius * 0.86, -f + 0.008),
		Vector2(radius * 0.955, -f * 0.62),
		Vector2(radius, -f * 0.34),
		Vector2(radius, f * 0.34),
		Vector2(radius * 0.955, f * 0.62),
		Vector2(radius * 0.86, f - 0.008),
		Vector2(rb, f),
	]
	var mesh: ArrayMesh = null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		# One group for the whole carcass so the sidewall and shoulder merge into
		# a curve; the tread gets its own so the shoulder keeps a crease.
		st.set_smooth_group(11 if i == 3 else 10)
		for k in SEG:
			var a0 := TAU * float(k) / float(SEG)
			var a1 := TAU * float(k + 1) / float(SEG)
			_quad(st, _lathe(prof[i], a0), _lathe(prof[i + 1], a0),
				_lathe(prof[i + 1], a1), _lathe(prof[i], a1))
	# Inboard face: a flat annulus back to the hub line, so looking under an arch
	# does not look straight through the wheel.
	st.set_smooth_group(-1)
	for k in SEG:
		var a0 := TAU * float(k) / float(SEG)
		var a1 := TAU * float(k + 1) / float(SEG)
		_quad(st, _lathe(Vector2(0.0, -f), a0), _lathe(Vector2(rb, -f), a0),
			_lathe(Vector2(rb, -f), a1), _lathe(Vector2(0.0, -f), a1))
	st.generate_normals()
	mesh = st.commit(mesh)
	# Surface 1: the whitewall band, 1.5 mm proud of the sidewall it lies on.
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	sw.set_smooth_group(12)
	var w0 := Vector2(rb * 1.01, f + 0.0015)
	var w1 := Vector2(radius * 0.855, f - 0.0065)
	# FOUND BY MEASUREMENT, cycle 2: this band was wound INSIDE-OUT. The carcass
	# profile above runs inboard bead -> tread -> outboard bead (radius falling as
	# x rises on the outer sidewall); the whitewall ran w0 -> w1, i.e. radius
	# RISING as x falls — the opposite way round the same surface, so its
	# generated normal came out at n.x = -0.994 and back-face culling deleted the
	# whitewall from every angle a player can stand in. The Slab is the only
	# profile with `whitewall: true`, so its one piece of period jewellery has
	# never once been on screen. w1 first puts it back the right way out.
	for k in SEG:
		var a0 := TAU * float(k) / float(SEG)
		var a1 := TAU * float(k + 1) / float(SEG)
		_quad(sw, _lathe(w1, a0), _lathe(w0, a0), _lathe(w0, a1), _lathe(w1, a1))
	sw.generate_normals()
	mesh = sw.commit(mesh)
	_face_meshes[key] = mesh
	return mesh


static func _lathe(pt: Vector2, a: float) -> Vector3:
	return Vector3(pt.y, pt.x * cos(a), pt.x * sin(a))


## Spoke blades, emitted into the rim surface as solid tapered wedges running
## from the pocket wall to the hub boss. They CONVERGE because each is built
## along its own radius, not stamped out as a rotated full-diameter bar.
## D-068: the blade faces now sit level with the flange crest (and so with the
## tyre's bead — never proud of it, which is what made the old D-017 rim a fan of
## floating plates). Against a pocket floor 32 mm behind them they read as spokes
## with holes between them instead of a texture on a disc.
static func _spokes(st: SurfaceTool, radius: float, face: float, r_pk: float,
		r_hub: float, cfg: Dictionary) -> void:
	var n := int(cfg["n"])
	var hw_o: float = radius * float(cfg["hw_o"])
	var hw_i: float = radius * float(cfg["hw_i"])
	var r0 := r_hub * 1.02                     # hub end
	var r1 := r_pk * 1.010                     # rim end, buried in the pocket wall
	var x_f := face + 0.002                    # blade faces level with the flange
	var x_b := face - 0.032                    # crest; the pocket behind is shadow
	var ex := Vector3(1.0, 0.0, 0.0)           # the axle
	var t2 := (x_f - x_b) * 0.5
	st.set_smooth_group(-1)                    # blades are faceted, the rim is not
	for k in n:
		var a := TAU * float(k) / float(n)
		var ez := Vector3(0.0, sin(a), -cos(a))           # tangential
		var outer := Vector3((x_f + x_b) * 0.5, cos(a) * r1, sin(a) * r1)
		var inner := Vector3((x_f + x_b) * 0.5, cos(a) * r0, sin(a) * r0)
		# Corner order mirrors mesh_kit.taper's (b0..b3 at -Y, t0..t3 at +Y), so
		# the six faces below carry the engine's front-face winding.
		var b := [outer - ex * t2 - ez * hw_o, outer + ex * t2 - ez * hw_o,
			outer + ex * t2 + ez * hw_o, outer - ex * t2 + ez * hw_o]
		var t := [inner - ex * t2 - ez * hw_i, inner + ex * t2 - ez * hw_i,
			inner + ex * t2 + ez * hw_i, inner - ex * t2 + ez * hw_i]
		_quad(st, b[0], b[3], b[2], b[1])
		_quad(st, t[0], t[1], t[2], t[3])
		_quad(st, b[0], b[1], t[1], t[0])
		_quad(st, b[1], b[2], t[2], t[1])
		_quad(st, b[2], b[3], t[3], t[2])
		_quad(st, b[3], b[0], t[0], t[3])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _f(key: String, def: float) -> float:
	return float(p.get(key, def))


func _vec3(v: Variant) -> Vector3:
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ONE


func _color(v: Variant) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.WHITE
