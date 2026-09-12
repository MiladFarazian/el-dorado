extends Node
## BUSTED — the second fail state (D-056). GTA has two ways to lose a chase; this
## game had one. A repo man who stops moving with the law within reach gets the
## cuffs: a cruiser pulled up alongside a still Book, or an officer at arm's
## length, for hold_s → the card → he wakes on the Longhorn Impound lot beside
## the wrecker, lighter by a fine that scales with the stars. (The repo man,
## impounded. Book would enjoy the joke less than we do.) on_foot.gd owns the
## card and the respawn; this system only decides WHEN. Data: arrest.json.

const DATA_PATH := "res://data/mechanics/arrest.json"
const LAYER := 12
const WARN_FONT := 26
const WARN_COLOR := Color(0.95, 0.90, 0.80)

var hold := 0.0                       # PUBLIC: s the cuffs have been closing
var cfg: Dictionary = {}
var main_ref: Node = null
var _disabled := false
var _ui: CanvasLayer = null
var _warn: Label = null


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true
		set_physics_process(false)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	_build_ui()


func _n(key: String, def: float) -> float:
	var v: Variant = cfg.get(key, def)
	return float(v) if (v is float or v is int) else def


func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	var pol := _peer("police")
	if pol == null:
		return
	var hv: Variant = pol.get("heat")
	var heat := int(hv) if hv is int else 0
	var of := _peer("on_foot")
	var down: bool = of != null and of.has_method("player_down") and of.call("player_down") == true
	if heat < int(_n("min_heat", 1)) or down:
		_set_hold(0.0)
		return
	var actor := _actor()
	if actor == null or _actor_speed(actor) > _n("player_still_mps", 1.6) \
			or not _law_in_reach(pol, actor.global_position):
		_set_hold(maxf(hold - delta * 2.0, 0.0))  # the cuffs open twice as fast as they close
		return
	_set_hold(hold + delta)
	if hold >= _n("hold_s", 1.8):
		_bust(heat, of)


## An officer on his feet at arm's length, or a cruiser stopped alongside.
func _law_in_reach(pol: Node, pos: Vector3) -> bool:
	var oreach := _n("officer_reach_m", 2.6)
	for n: Node in get_tree().get_nodes_in_group("officer"):
		if n is RigidBody3D and is_instance_valid(n) and (n as RigidBody3D).freeze \
				and (n as Node3D).global_position.distance_to(pos) <= oreach:
			return true
	var creach := _n("cruiser_reach_m", 5.0)
	var cstill := _n("cruiser_still_mps", 2.5)
	var cruisers: Variant = pol.get("cruisers")
	if cruisers is Array:
		for c: Variant in cruisers:
			if not (c is Dictionary):
				continue
			var b: Variant = (c as Dictionary).get("body")
			if b is RigidBody3D and is_instance_valid(b) and (b as Node).is_inside_tree() \
					and (b as RigidBody3D).linear_velocity.length() <= cstill \
					and (b as Node3D).global_position.distance_to(pos) <= creach:
				return true
	return false


func _bust(heat: int, of: Node) -> void:
	var fine := clampi(int(_n("fine_per_star", 150)) * heat,
		int(_n("fine_min", 150)), int(_n("fine_max", 900)))
	_set_hold(0.0)
	if of != null and of.has_method("arrest"):
		of.call("arrest", fine)


func _set_hold(v: float) -> void:
	hold = v
	if _warn == null:
		return
	var warn_after := _n("warning_s", 0.5)
	_warn.visible = hold > warn_after
	if _warn.visible:
		var f := clampf((hold - warn_after) / maxf(_n("hold_s", 1.8) - warn_after, 0.1), 0.0, 1.0)
		_warn.modulate.a = 0.55 + 0.45 * f
		_warn.text = "HANDS ON THE HOOD." if f < 0.6 else "HANDS ON THE HOOD. NOW."


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = LAYER
	add_child(_ui)
	_warn = Label.new()
	_warn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 176)
	_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warn.add_theme_font_size_override("font_size", WARN_FONT)
	_warn.add_theme_color_override("font_color", WARN_COLOR)
	_warn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_warn.add_theme_constant_override("outline_size", 7)
	_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_warn.visible = false
	_ui.add_child(_warn)


# ============================== PLUMBING =====================================
func _actor() -> Node3D:
	var key := "character" if main_ref.get("on_foot") == true else "vehicle"
	var a: Variant = main_ref.get(key)
	if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
		return a
	return null


func _actor_speed(a: Node3D) -> float:
	if a is RigidBody3D:
		return (a as RigidBody3D).linear_velocity.length()
	if a is CharacterBody3D:
		return (a as CharacterBody3D).velocity.length()
	return 0.0


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null
