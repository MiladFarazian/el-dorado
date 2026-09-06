extends Node
## TIRE FX (M23) — skid marks and tyre smoke for the player's vehicle and the
## cruisers chasing it. Reads the per-wheel readouts raycast_vehicle publishes
## (`contact`, `normal`, `lat_slip`, `slide`, `fwd_speed`, `grounded`); writes
## nothing back. A wheel is SLIDING when its friction circle is saturated
## (slide >= 1.0) with real lateral or longitudinal motion, or when the handbrake
## locks a rear at speed — the same threshold family vehicle_audio uses for the
## skid noise, so the sound and the mark agree.
##
## Marks: ONE MultiMesh of flat quads (ring buffer, MARKS instances), laid at the
## contact point along the wheel's travel, alpha by slide intensity, aged out by
## shrinking to zero. Shadow policy: flat decal -> casts OFF. Smoke: a small pool
## of CPUParticles3D parked on sliding wheels. §4b: O(tracked wheels) per tick,
## at most 6 vehicles x 4 wheels; nothing per instance per frame.
## ENTIRELY INERT in smoke mode.

const MARKS := 480                     # ring buffer of skid quads
const MARK_LEN := 0.55                 # m per segment
const MARK_W := 0.22                   # m (tyre tread width read)
const MARK_LIFT := 0.012               # m above the surface (z-fight margin)
const MARK_LIFE := 40.0                # s before a mark starts fading
const MARK_FADE := 12.0                # s of fade
const MARK_STEP := 0.45                # m of travel between segments per wheel
const SLIDE_ON := 1.0                  # friction circle saturated
const LAT_ON := 3.0                    # m/s lateral slip that marks on its own
const SPEED_MIN := 4.0                 # m/s: crawling never marks
const SMOKE_POOL := 12
const SMOKE_AMOUNT := 18
const SMOKE_LIFE := 1.3
const MARK_COLOR := Color(0.05, 0.05, 0.055, 1.0)

var main_ref: Node = null
var _mm: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _head := 0
var _born := PackedFloat32Array()      # s each instance was laid (-1 = empty)
var _last_lay: Dictionary = {}          # wheel key -> last contact laid
var _smoke: Array[CPUParticles3D] = []
var _smoke_owner: Dictionary = {}       # wheel key -> pool index
var _t := 0.0
var _accum := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return
	_build_marks()
	_build_smoke()


func _build_marks() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(MARK_W, MARK_LEN)
	quad.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.albedo_color = MARK_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = MARKS
	_born.resize(MARKS)
	for i in MARKS:
		_born[i] = -1.0
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0)))
		_mm.set_instance_color(i, Color(0, 0, 0, 0))
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "SkidMarks"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # flat decal
	_mmi.custom_aabb = AABB(Vector3(-2000, -50, -2000), Vector3(4000, 200, 4000))
	main_ref.add_child(_mmi)


## CPU particles on purpose: twelve emitters of eighteen puffs cost nothing, and
## the GPU path left `1 shaders of type ParticlesShaderRD were never freed` at
## every windowed exit (meas7 runs 28-33, bisected to this file) whatever the
## teardown order — CPU particles have no process shader to leak.
func _build_smoke() -> void:
	var curve := Curve.new(); curve.add_point(Vector2(0, 0.5)); curve.add_point(Vector2(1, 2.2))
	var grad := Gradient.new()
	grad.set_color(0, Color(0.82, 0.82, 0.84, 0.55)); grad.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	var quad := QuadMesh.new(); quad.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	quad.material = m
	for i in SMOKE_POOL:
		var p := CPUParticles3D.new()
		p.name = "TyreSmoke%d" % i
		p.mesh = quad
		p.amount = SMOKE_AMOUNT
		p.lifetime = SMOKE_LIFE
		p.emitting = false
		p.local_coords = false
		p.direction = Vector3(0, 1, 0)
		p.spread = 35.0
		p.initial_velocity_min = 0.6; p.initial_velocity_max = 1.6
		p.gravity = Vector3(0, 0.9, 0)
		p.damping_min = 0.8; p.damping_max = 1.4
		p.scale_amount_min = 0.35; p.scale_amount_max = 0.8
		p.scale_amount_curve = curve
		p.color_ramp = grad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main_ref.add_child(p)
		_smoke.append(p)


func _physics_process(delta: float) -> void:
	_t += delta
	var active: Dictionary = {}
	for v in _tracked():
		var ws: Variant = v.get("wheels")
		if not (ws is Array):
			continue
		var spd := (v as RigidBody3D).linear_velocity.length()
		var hb: bool = v.get("ext_handbrake") == true or (v.get("player_controlled") == true \
			and InputMap.has_action("handbrake") and Input.is_action_pressed("handbrake"))  # gotcha: get()==true needs an explicit type
		var wi := 0
		for w: Dictionary in (ws as Array):
			wi += 1
			if not bool(w.get("grounded", false)) or spd < SPEED_MIN:
				continue
			var lat := absf(float(w.get("lat_slip", 0.0)))
			var slide := float(w.get("slide", 0.0))
			var sliding: bool = lat > LAT_ON or slide >= SLIDE_ON or (hb and bool(w.get("rear", false)) and spd > SPEED_MIN)
			if not sliding:
				continue
			var key := "%d_%d" % [v.get_instance_id(), wi]
			active[key] = true
			var c: Vector3 = w.get("contact", Vector3.ZERO)
			var n: Vector3 = w.get("normal", Vector3.UP)
			var travel: Vector3 = (v as RigidBody3D).linear_velocity
			travel -= n * travel.dot(n)
			var strength := clampf(maxf(lat / 8.0, slide - 0.6), 0.25, 1.0)
			_lay(key, c, n, travel, strength)
			_smoke_at(key, c + n * 0.05, strength)
	# Park the smoke of wheels that stopped sliding.
	for key in _smoke_owner.keys():
		if not active.has(key):
			_smoke[_smoke_owner[key]].emitting = false
			_smoke_owner.erase(key)
	_accum += delta
	if _accum >= 0.5:
		_accum = 0.0
		_age_marks()


func _lay(key: String, c: Vector3, n: Vector3, travel: Vector3, strength: float) -> void:
	var last: Vector3 = _last_lay.get(key, Vector3(1e9, 0, 0))
	if last.distance_to(c) < MARK_STEP:
		return
	_last_lay[key] = c
	var fwd := travel.normalized() if travel.length() > 0.1 else Vector3.FORWARD
	var basis := Basis.looking_at(fwd, n)
	_mm.set_instance_transform(_head, Transform3D(basis, c + n * MARK_LIFT))
	_mm.set_instance_color(_head, Color(1, 1, 1, 0.55 * strength))
	_born[_head] = _t
	_head = (_head + 1) % MARKS


func _age_marks() -> void:
	for i in MARKS:
		var b := _born[i]
		if b < 0.0:
			continue
		var age := _t - b
		if age > MARK_LIFE + MARK_FADE:
			_born[i] = -1.0
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0)))
		elif age > MARK_LIFE:
			var col := _mm.get_instance_color(i)
			col.a = col.a * (1.0 - (age - MARK_LIFE) / MARK_FADE)
			_mm.set_instance_color(i, col)


func _smoke_at(key: String, pos: Vector3, strength: float) -> void:
	var idx := -1
	if _smoke_owner.has(key):
		idx = int(_smoke_owner[key])
	else:
		for i in _smoke.size():
			if not _smoke_owner.values().has(i):
				idx = i
				break
		if idx < 0:
			return
		_smoke_owner[key] = idx
	var p := _smoke[idx]
	p.global_position = pos
	p.speed_scale = clampf(0.6 + strength * 0.6, 0.6, 1.2)
	p.emitting = true


## Release GPU resources while the RenderingServer is still alive: a
## ParticleProcessMaterial shared by twelve emitters outlived renderer teardown
## and printed `ParticlesShaderRD were never freed` at exit (gate §5: an ERROR).
func _exit_tree() -> void:
	for p in _smoke:
		if is_instance_valid(p):
			p.emitting = false
	_smoke.clear()
	_smoke_owner.clear()
	if _mmi != null and is_instance_valid(_mmi):
		_mmi.multimesh = null
		_mmi.queue_free()
	_mm = null


## The player's vehicle plus pursuing cruisers — bounded, never traffic.
func _tracked() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var pv: Variant = main_ref.get("vehicle")
	if pv is RigidBody3D and is_instance_valid(pv) and (pv as Node3D).is_inside_tree():
		out.append(pv as RigidBody3D)
	for n in get_tree().get_nodes_in_group("police"):
		if n is RigidBody3D and is_instance_valid(n) and (n as Node3D).is_inside_tree() and out.size() < 6:
			out.append(n as RigidBody3D)
	return out
