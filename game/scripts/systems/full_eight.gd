extends Node
## THE FULL EIGHT — Book's special ability (story bible §4; D-056).
## Eight seconds of bull-rider time dilation. The meter is a bull rope: it fills
## while Book is HOLDING ON — speed, air, a hot tow, a near miss, the slab strip,
## a star shaken off — and pays out while the world runs at a third speed. Fire
## it on CAPS LOCK / X (GTA's key, and one that works on a laptop). Every number
## lives in data/mechanics/full_eight.json.
##
## Time authority: this system owns Engine.time_scale while `active`; the weapon
## wheel (combat.gd) restores through active_time_scale() so the two never fight.
## The audio mix follows via AudioServer.playback_speed_scale — the engine note,
## the radio, the sirens all drop with the world, which is the signature sound.

signal fired
signal ended

const DATA_PATH := "res://data/mechanics/full_eight.json"
const VEIL_LAYER := 5                 # under every HUD layer (hud_gta is 10)
const NEAR_SCAN := 0.1                # s between near-miss scans
const NEAR_REPEAT := 3.0              # s before the same car counts again
const NEAR_PAD := 2.4                 # m of body half-widths between two origins
const FIRE_TRAUMA := 0.14             # a small kick when it lands
const VEIL_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 1.0;
void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 warm = mix(c.rgb, vec3(g) * vec3(1.08, 0.98, 0.84), 0.45 * amount);
	vec2 d = SCREEN_UV - vec2(0.5);
	float vig = smoothstep(0.28, 0.95, dot(d, d) * 2.4);
	warm *= 1.0 - 0.55 * vig * amount;
	COLOR = vec4(warm, 1.0);
}
"""

# ============================== PUBLIC =======================================
var charge := 0.0                     # 0..1 — the rope (HUD reads it)
var active := false                   # the world is slowed
var active_left := 0.0                # real seconds left on the ride
var chain_held := false               # tow_hook: the chain will not snap
var cfg: Dictionary = {}

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _cooldown := 0.0
var _near_t := 0.0
var _near_seen: Dictionary = {}       # instance id -> real time of last count
var _clock := 0.0                     # real seconds since boot (unscaled)
var _last_heat := 0
var _ui: CanvasLayer = null
var _veil: ColorRect = null
var _veil_w := 0.0
var _grip_veh: Node = null            # the ride carrying grip_bonus right now


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true
		set_physics_process(false); set_process(false)
		return
	cfg = _load_cfg()
	_build_veil()
	_late_bind.call_deferred()   # peers load alphabetically after us (police, slab_cruise)


func _load_cfg() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_warning("FULL EIGHT: %s missing, defaults in force" % DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _n(key: String, def: float) -> float:
	var v: Variant = cfg.get(key, def)
	return float(v) if (v is float or v is int) else def


func _late_bind() -> void:
	var pol := _peer("police")
	if pol != null and pol.has_signal("heat_changed"):
		pol.connect("heat_changed", _on_heat_changed)
		var hv: Variant = pol.get("heat")
		_last_heat = int(hv) if hv is int else 0
	var strip := _peer("slab_cruise")
	if strip != null and strip.has_signal("strip_tick"):
		strip.connect("strip_tick", _on_strip_tick)


## PUBLIC (combat.gd): what the world's time scale is with the wheel closed.
func active_time_scale() -> float:
	return _n("time_scale", 0.35) if active else 1.0


func on_vehicle_changed(v: Node) -> void:
	# The grip bonus follows the ride: never leave 1.3x on a car Book stepped out of.
	if _grip_veh != null and is_instance_valid(_grip_veh) and _grip_veh != v:
		_grip_veh.set("grip_bonus", 1.0)
	_grip_veh = null
	if active and v is RigidBody3D and is_instance_valid(v):
		v.set("grip_bonus", _n("grip_bonus", 1.30))
		_grip_veh = v


# ============================== PER FRAME ====================================
func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)  # the fixed step is game time
	_clock += real
	_cooldown = maxf(_cooldown - real, 0.0)
	var down := _player_down()
	if active:
		active_left -= real
		charge = clampf(active_left / maxf(_n("duration_s", 8.0), 0.1), 0.0, 1.0)
		if active_left <= 0.0 or down or _pressed():
			_end()
		return
	if down:
		return
	_charge(real)
	if _pressed() and _cooldown <= 0.0 and charge >= _n("min_charge_to_fire", 0.25):
		_fire()


func _process(delta: float) -> void:
	if _veil == null:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	_veil_w = lerpf(_veil_w, 1.0 if active else 0.0, 1.0 - exp(-8.0 * real))
	_veil.visible = _veil_w > 0.01
	if _veil.material is ShaderMaterial:
		(_veil.material as ShaderMaterial).set_shader_parameter("amount", _veil_w)


func _pressed() -> bool:
	return InputMap.has_action("special") and Input.is_action_just_pressed("special")


# ============================== HOLDING ON ===================================
## Every source is Book at the edge of control. Charge accrues in REAL seconds.
func _charge(real: float) -> void:
	var veh := _driving_vehicle()
	if veh == null:
		return
	var speed := veh.linear_velocity.length()
	var add := 0.0
	if speed >= _n("charge_speed_threshold_mps", 18.0):
		add += _n("charge_speed_per_s", 0.028) * real
	if speed > 4.0 and not _any_wheel_grounded(veh):
		add += _n("charge_air_per_s", 0.16) * real
	var tow := _peer("tow_hook")
	if tow != null and tow.get("hooked_body") != null and speed >= _n("charge_tow_speed_mps", 8.0):
		add += _n("charge_tow_per_s", 0.05) * real
	_near_t -= real
	if _near_t <= 0.0:
		_near_t = NEAR_SCAN
		add += _near_misses(veh)
	if add > 0.0:
		charge = clampf(charge + add, 0.0, 1.0)


## A car passed within the gap at closing speed, and it was not the one on the hook.
func _near_misses(veh: RigidBody3D) -> float:
	var total := 0.0
	var pv := veh.linear_velocity
	var pp := veh.global_position
	var gap_max := _n("near_miss_dist_m", 2.2)
	var rel_min := _n("near_miss_rel_speed_mps", 14.0)
	var tow := _peer("tow_hook")
	var hooked: Variant = tow.get("hooked_body") if tow != null else null
	for g: String in ["civilian", "police"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if not (n is RigidBody3D) or not is_instance_valid(n) or n == veh or n == hooked:
				continue
			var b := n as RigidBody3D
			if b.global_position.distance_to(pp) - NEAR_PAD > gap_max:
				continue
			if (pv - b.linear_velocity).length() < rel_min:
				continue
			var id := b.get_instance_id()
			if _near_seen.has(id) and _clock - float(_near_seen[id]) < NEAR_REPEAT:
				continue
			_near_seen[id] = _clock
			total += _n("charge_near_miss", 0.06)
	return total


func _on_strip_tick(_amount: int) -> void:
	if not active:
		charge = clampf(charge + _n("charge_strip_tick", 0.05), 0.0, 1.0)


## A star shaken off is holding on. The hospital's clean slate is not (player down).
func _on_heat_changed(heat: int) -> void:
	if heat < _last_heat and not active and not _player_down():
		charge = clampf(charge + _n("charge_evaded_star", 0.10) * float(_last_heat - heat), 0.0, 1.0)
	_last_heat = heat


# ============================== THE RIDE =====================================
func _fire() -> void:
	active = true
	active_left = charge * _n("duration_s", 8.0)
	Engine.time_scale = _n("time_scale", 0.35)
	AudioServer.playback_speed_scale = _n("audio_pitch", 0.55)
	chain_held = cfg.get("chain_unbreakable", true) == true
	_set_grip(_n("grip_bonus", 1.30))
	var cam: Variant = main_ref.get("camera")
	if cam is Node and is_instance_valid(cam) and (cam as Node).has_method("add_trauma"):
		(cam as Node).call("add_trauma", FIRE_TRAUMA)
	fired.emit()


func _end() -> void:
	active = false
	active_left = 0.0
	charge = 0.0
	chain_held = false
	_cooldown = _n("cooldown_s", 6.0)
	_set_grip(1.0)
	AudioServer.playback_speed_scale = 1.0
	var combat := _peer("combat")
	var wheel_open: bool = combat != null and combat.get("_wheel_open") == true  # gotcha: `:=` cannot infer
	Engine.time_scale = 0.3 if wheel_open else 1.0   # the wheel keeps its own slow-mo
	ended.emit()


func _set_grip(bonus: float) -> void:
	if _grip_veh != null and is_instance_valid(_grip_veh):
		_grip_veh.set("grip_bonus", 1.0)
	_grip_veh = null
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v):
		(v as Node).set("grip_bonus", bonus)
		_grip_veh = v if bonus != 1.0 else null


func _build_veil() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = VEIL_LAYER
	add_child(_ui)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_veil.color = Color.WHITE
	var sh := Shader.new()
	sh.code = VEIL_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("amount", 0.0)
	_veil.material = sm
	_veil.visible = false
	_ui.add_child(_veil)


# ============================== PLUMBING =====================================
func _driving_vehicle() -> RigidBody3D:
	if main_ref.get("on_foot") == true:
		return null
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


func _any_wheel_grounded(veh: RigidBody3D) -> bool:
	var ws: Variant = veh.get("wheels")
	if not (ws is Array):
		return true
	for w: Variant in ws:
		if w is Dictionary and (w as Dictionary).get("grounded", true) == true:
			return true
	return false


func _player_down() -> bool:
	var of := _peer("on_foot")
	return of != null and of.has_method("player_down") and of.call("player_down") == true


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null
