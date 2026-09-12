extends Node
## VEHICLE DAMAGE (M23) — crumple on impact. A hard hit is a per-tick velocity
## change above DV_MIN on a contact-monitored vehicle; the hull mesh (the
## builder's "Hull", duplicated per vehicle on first dent so no other car of the
## same style shares the damage) is pushed inward around the extreme point in
## the impact direction, with a falloff and a little per-vertex hash so no two
## dents match, and normals are rebuilt. Hull points and engine power go through
## the SAME meta and rule police_gunfire uses (`gunfire_hull`), so a rammed car
## sputters the way a shot one does. VISUAL + meta ONLY: the collision shape is
## never touched (physics sacred). Tracks the player's vehicle and pursuing
## cruisers (they already contact-monitor). Reset teleports are ignored. Inert
## in smoke mode.

const DV_MIN := 4.0                  # m/s of velocity change that counts as a hit
const DEPTH_PER_MPS := 0.022         # m of dent per m/s over DV_MIN
const DEPTH_MAX := 0.24
const RADIUS_BASE := 0.55            # m, dent radius at DV_MIN
const RADIUS_PER_MPS := 0.05
const RADIUS_MAX := 1.15
const CRASH_DMG_PER_MPS := 1.4       # hull points per m/s of impact
const SPUTTER_FRAC := 0.55           # mirrors police_gunfire
const MIN_POWER := 0.35
const HULL_META := "gunfire_hull"; const HULL_MAX_META := "gunfire_hull_max"
const RESET_GRACE := 3               # physics frames after a reset to ignore

var main_ref: Node = null
var _state: Dictionary = {}          # instance id -> {v, last_vel, dents}
var dent_count := 0                  # PUBLIC (probe)


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return


func on_vehicle_changed(v: Node) -> void:
	_track(v)


func _track(v: Node) -> void:
	if not (v is RigidBody3D) or not is_instance_valid(v):
		return
	var rb := v as RigidBody3D
	if not rb.contact_monitor:
		rb.contact_monitor = true
		rb.max_contacts_reported = maxi(rb.max_contacts_reported, 6)
	if not _state.has(rb.get_instance_id()):
		_state[rb.get_instance_id()] = {"v": rb, "last_vel": rb.linear_velocity, "dents": 0}


func _physics_process(_d: float) -> void:
	var pv: Variant = main_ref.get("vehicle")
	if pv is RigidBody3D:
		_track(pv)
	for n in get_tree().get_nodes_in_group("police"):
		if n is RigidBody3D and _state.size() < 8:
			_track(n)
	for id in _state.keys():
		var st: Dictionary = _state[id]
		# D-056/D-121: a freed cruiser (heat clear, despawn) must be checked as a
		# Variant — assigning it to a typed RigidBody3D is itself the SCRIPT ERROR.
		var vv: Variant = st["v"]
		if not is_instance_valid(vv) or not (vv is RigidBody3D) or not (vv as Node).is_inside_tree():
			_state.erase(id); continue
		var v := vv as RigidBody3D
		var vel := v.linear_velocity
		var dv := vel - (st["last_vel"] as Vector3)
		st["last_vel"] = vel
		var lrf: Variant = v.get("last_reset_frame")
		if lrf is int and Engine.get_physics_frames() - int(lrf) <= RESET_GRACE:
			continue
		var mag := dv.length()
		if mag < DV_MIN:
			continue
		# A hard hit. The car decelerated along dv; it was struck from -dv.
		_dent(v, -dv.normalized(), mag, st)


func _dent(v: RigidBody3D, from_dir_world: Vector3, mag: float, st: Dictionary) -> void:
	var hull := _hull(v)
	if hull == null:
		return
	var mesh := hull.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	if int(st["dents"]) == 0:
		mesh = mesh.duplicate() as ArrayMesh   # this car's own copy from now on
		hull.mesh = mesh
	var dir_local: Vector3 = (hull.global_transform.basis.inverse() * from_dir_world).normalized()
	var depth := clampf((mag - DV_MIN) * DEPTH_PER_MPS + 0.03, 0.03, DEPTH_MAX)
	var radius := clampf(RADIUS_BASE + (mag - DV_MIN) * RADIUS_PER_MPS, RADIUS_BASE, RADIUS_MAX)
	# MeshDataTool only: it preserves vertex order and the builder's designed
	# hard creases; only the dented vertices get a recomputed (smoothed) normal.
	# (A SurfaceTool rebuild re-indexed 3,696 -> 841 vertices and softened every
	# crease on the car — crash probe, first run.)
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, s) != OK:
			continue
		var best := -1e9; var centre := Vector3.ZERO
		for i in mdt.get_vertex_count():
			var d := mdt.get_vertex(i).dot(dir_local)
			if d > best:
				best = d; centre = mdt.get_vertex(i)
		var moved: PackedInt32Array = PackedInt32Array()
		for i in mdt.get_vertex_count():
			var p := mdt.get_vertex(i)
			var dist := p.distance_to(centre)
			if dist >= radius:
				continue
			var t := 1.0 - dist / radius
			var h := 0.75 + 0.5 * fposmod(sin(p.x * 91.7 + p.y * 57.1 + p.z * 33.3) * 43758.5, 1.0)
			mdt.set_vertex(i, p - dir_local * depth * t * t * h)
			moved.append(i)
		for i in moved:
			var nsum := Vector3.ZERO
			for f in mdt.get_vertex_faces(i):
				nsum += mdt.get_face_normal(f)
			if nsum.length_squared() > 1e-8:
				mdt.set_vertex_normal(i, nsum.normalized())
		mdt.commit_to_surface(out)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	hull.mesh = out
	st["dents"] = int(st["dents"]) + 1
	dent_count += 1
	# hull points + power, the gunfire model
	var mx := _hull_max(v)
	var hp := float(v.get_meta(HULL_META, mx)) - mag * CRASH_DMG_PER_MPS
	v.set_meta(HULL_META, hp)
	var pm := 1.0
	if hp <= 0.0:
		pm = 0.0
	else:
		var frac := clampf(hp / mx, 0.0, 1.0)
		if frac < SPUTTER_FRAC:
			pm = lerpf(MIN_POWER, 1.0, frac / SPUTTER_FRAC)
	v.set("power_modifier", pm)


func _hull_max(v: RigidBody3D) -> float:
	if v.has_meta(HULL_MAX_META):
		return float(v.get_meta(HULL_MAX_META))
	var mx := 100.0
	var prof: Variant = v.get("p")
	if prof is Dictionary:
		mx = float((prof as Dictionary).get("hull", 100.0))
	v.set_meta(HULL_MAX_META, mx)
	v.set_meta(HULL_META, mx)
	return mx


## The builder names the tub "Hull"; find it under the vehicle, not by index.
func _hull(v: Node) -> MeshInstance3D:
	var h := v.find_child("Hull", true, false)
	return h as MeshInstance3D if h is MeshInstance3D else null
