extends Node
## HUD (M23) — the GTA-style heads-up display. One system owns everything the
## player reads at a glance: a heading-up radar (bottom-left) with the health and
## stamina bars under it, wanted stars + weapon/ammo + cash (top-right), the live
## objective line and a context-aware control hint (bottom-centre).
##
## LAWS THIS FILE OBEYS
##  * "The HUD never lies" (bar §4). Every value is read FROM the thing it
##    reports: `main.player_actor()` for position/heading (D-031 — the old debug
##    HUD kept quoting the parked truck while you walked), planar speed (D-032),
##    combat's live weapon/mag/reserve, police.heat, player stamina/health,
##    repo_board.money. Nothing is cached across frames except eased widths.
##  * Every Control is MOUSE_FILTER_IGNORE (a STOP control at screen centre eats
##    captured-mouse look; parent IGNORE does not propagate).
##  * Inert in smoke mode. Null-safe against every peer: a missing system just
##    leaves its element blank.
##  * §4b: the radar redraws at 20 Hz; labels update per frame but are O(1).
##
## PEERS THAT DEFER TO THIS FILE when `main.systems.has("hud_gta")`: police.gd
## hides its own star row (we draw 5), repo_board.gd hides its bottom-right panel
## (we draw cash + objective), combat.gd hides its health/ammo band (we draw both)
## but KEEPS the crosshair/spread ring — that is a gameplay instrument, not HUD.
##
## GEOMETRY SOURCES (read-only): city_dressing NS_X/EW_Z (downtown grid),
## greybox_city FWY_*/FRONTAGE_Z/RAMP_*/CH_*/SUB_* (freeway, frontage, ramps,
## the Threefork floodway — drawn as the CONCRETE it is, fixing D-035 — and the
## Stonebridle lanes), plus the hospital and impound markers.

const DRESS := preload("res://scripts/world/city_dressing.gd")
const CITY := preload("res://scripts/world/greybox_city.gd")

# ============================== LAYOUT ========================================
const LAYER := 10                     # debug HUD (F3) shares 10; police 12 hides its stars
const MARGIN := 18.0
const RADAR_W := 300.0                # GTA V's radar is a wide rounded rectangle
const RADAR_H := 170.0
const RADAR_RADIUS := 14.0            # corner rounding
const RADAR_RANGE := 150.0            # metres across HALF the radar width
const RADAR_HZ := 20.0
const BAR_H := 7.0                    # health / stamina bar height
const BAR_GAP := 3.0
const STAR_SIZE := 30
const STAR_COUNT := 5                 # GTA scale; police.MAX_HEAT may be lower — dim the rest
const FONT_HUD := 19
const FONT_AMMO := 26
const FONT_CASH := 24
const FONT_OBJ := 18
const FONT_HINT := 14
const FONT_PROMPT := 22
const PROMPT_RANGE := 3.6             # = on_foot.ENTER_RANGE: "E — ENTER" appears here
const HINT_FADE_S := 6.0              # the verb sheet fades after a mode change

# ============================== PALETTE =======================================
const C_RADAR_BG := Color(0.07, 0.08, 0.09, 0.82)
const C_RADAR_LAND := Color(0.16, 0.17, 0.15, 1.0)
const C_ROAD := Color(0.62, 0.62, 0.60, 1.0)
const C_ROAD_MINOR := Color(0.48, 0.48, 0.47, 1.0)
const C_FWY := Color(0.86, 0.80, 0.55, 1.0)
const C_CONCRETE := Color(0.40, 0.41, 0.40, 1.0)   # the floodway floor (D-035)
const C_RIM := Color(0.92, 0.92, 0.92, 0.55)
const C_PLAYER := Color(1, 1, 1, 1)
const C_TRUCK := Color(0.40, 0.70, 1.0, 1)
const C_COP := Color(0.25, 0.55, 1.0, 1)          # GTA: cops are blue blips
const C_COP_CAR := Color(1.0, 0.30, 0.25, 1)      # cruisers: red/blue — red half
const C_TARGET := Color(1.0, 0.78, 0.20, 1)
const C_HOSPITAL := Color(0.95, 0.35, 0.35, 1)
const C_PAD := Color(0.55, 0.90, 0.55, 1)
const C_SEARCH := Color(1.0, 0.30, 0.25, 0.22)     # wanted search radius fill
const C_SEARCH_RIM := Color(1.0, 0.30, 0.25, 0.75)
const C_HEALTH := Color(0.36, 0.72, 0.35, 1)
const C_HEALTH_LOW := Color(0.85, 0.25, 0.20, 1)
const C_STAMINA := Color(0.90, 0.80, 0.35, 1)
const C_BAR_BG := Color(0, 0, 0, 0.55)
const C_TEXT := Color(0.96, 0.96, 0.96, 1)
const C_CASH := Color(0.55, 0.88, 0.45, 1)
const C_STAR_ON := Color(1.0, 1.0, 1.0, 1)
const C_STAR_OFF := Color(1.0, 1.0, 1.0, 0.18)
const C_OUTLINE := Color(0, 0, 0, 0.85)

# ============================== STATE =========================================
var main_ref: Node = null
var _ui: CanvasLayer = null
var _radar: Control = null
var _health_bg: ColorRect = null
var _health: ColorRect = null
var _stamina: ColorRect = null
var _stars: Array[Label] = []
var _weapon_lbl: Label = null
var _ammo_lbl: Label = null
var _cash_lbl: Label = null
var _obj_lbl: Label = null
var _hint_lbl: Label = null
var _prompt_lbl: Label = null
var _font: Font = null
var _font_bold: Font = null
var _accum := 0.0
var _health_w := 1.0                  # eased fractions so a hit reads as a sweep
var _stamina_w := 1.0
var _hint_left := 0.0
var _last_on_foot := -1               # -1 = unknown, forces the first hint
var _rot := 0.0                       # radar rotation this frame (rad)


# ============================== SETUP ========================================
func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return
	_font = _sys_font(500)
	_font_bold = _sys_font(800)
	_build()


## Rounded-rect mask for the radar: a canvas shader that discards every fragment
## outside the rounded rectangle. It applies to every draw_* call the Control
## makes, so roads never poke past the corners — no SubViewport, no CanvasGroup.
## NOTE: keyed on the LOCAL VERTEX position, never on UV — draw_line/draw_rect/
## draw_polygon primitives carry no meaningful UVs (they read as 0,0), so a UV
## mask discarded every road and blip and let only the text glyphs through.
const MASK_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(300.0, 170.0);
uniform float radius = 14.0;
varying vec2 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	vec2 q = abs(lp - size * 0.5) - (size * 0.5 - vec2(radius));
	float d = length(max(q, vec2(0.0))) - radius;
	if (d > 0.0) { discard; }
}
"""


func _build() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = LAYER
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# --- Radar, bottom-left, with the two bars under it.
	var bars_h := BAR_H + BAR_GAP
	_radar = Control.new()
	_radar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_radar.offset_left = MARGIN
	_radar.offset_right = MARGIN + RADAR_W
	_radar.offset_bottom = -(MARGIN + bars_h)
	_radar.offset_top = _radar.offset_bottom - RADAR_H
	_radar.clip_contents = true
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new(); sh.code = MASK_SHADER
	var sm := ShaderMaterial.new(); sm.shader = sh
	sm.set_shader_parameter("size", Vector2(RADAR_W, RADAR_H))
	sm.set_shader_parameter("radius", RADAR_RADIUS)
	_radar.material = sm
	_radar.draw.connect(_on_radar_draw)
	root.add_child(_radar)

	var bar_top := -(MARGIN + BAR_H)
	_health_bg = _rect(root, C_BAR_BG, MARGIN, bar_top, RADAR_W, BAR_H)
	var hw := RADAR_W * 0.58
	_health = _rect(root, C_HEALTH, MARGIN, bar_top, hw, BAR_H)
	_stamina = _rect(root, C_STAMINA, MARGIN + hw + 6.0, bar_top, RADAR_W - hw - 6.0, BAR_H)

	# --- Top-right stack: stars, weapon + ammo, cash.
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stack.offset_right = -MARGIN
	stack.offset_top = MARGIN
	stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_END
	star_row.add_theme_constant_override("separation", 4)
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(star_row)
	for i in STAR_COUNT:
		var st := _label("★", STAR_SIZE, C_STAR_OFF, _font_bold)
		star_row.add_child(st)
		_stars.append(st)
	_weapon_lbl = _label("", FONT_HUD, C_TEXT, _font_bold)
	_weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_weapon_lbl)
	_ammo_lbl = _label("", FONT_AMMO, C_TEXT, _font_bold)
	_ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_ammo_lbl)
	_cash_lbl = _label("", FONT_CASH, C_CASH, _font_bold)
	_cash_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_cash_lbl)

	# --- Bottom-centre: objective, then the verb hint, then the interact prompt.
	var mid := VBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mid.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mid.offset_bottom = -MARGIN
	mid.offset_left = -420.0; mid.offset_right = 420.0
	mid.alignment = BoxContainer.ALIGNMENT_END
	mid.add_theme_constant_override("separation", 4)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	_prompt_lbl = _label("", FONT_PROMPT, C_TEXT, _font_bold)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_prompt_lbl)
	_obj_lbl = _label("", FONT_OBJ, C_TARGET, _font_bold)
	_obj_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_obj_lbl)
	_hint_lbl = _label("", FONT_HINT, Color(0.85, 0.85, 0.85, 0.9), _font)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_hint_lbl)


# ============================== PER FRAME ====================================
func _process(delta: float) -> void:
	if _ui == null or main_ref == null:
		return
	var actor := _actor()
	var on_foot := bool(main_ref.get("on_foot"))
	_update_rotation(actor)
	_update_bars(delta, on_foot)
	_update_top_right()
	_update_bottom(delta, actor, on_foot)
	_accum += delta
	if _accum >= 1.0 / RADAR_HZ:
		_accum = 0.0
		if _radar != null and is_instance_valid(_radar):
			_radar.queue_redraw()


## Heading-up: rotate the world so the actor's forward points to screen-up.
func _update_rotation(actor: Node3D) -> void:
	if actor == null:
		return
	var fwd := -actor.global_transform.basis.z
	var f2 := Vector2(fwd.x, fwd.z)
	if f2.length_squared() < 1e-6:
		return
	_rot = -PI * 0.5 - f2.angle()


func _update_bars(delta: float, on_foot: bool) -> void:
	var ch: Variant = main_ref.get("character")
	var hfrac := 1.0
	var sfrac := 1.0
	if ch is Node and is_instance_valid(ch):
		var h: Variant = (ch as Node).get("health")
		var mh: Variant = (ch as Node).get("max_health")
		if (h is float or h is int):
			var top := float(mh) if (mh is float or mh is int) and float(mh) > 0.0 else 100.0
			hfrac = clampf(float(h) / top, 0.0, 1.0)
		var st: Variant = (ch as Node).get("stamina")
		if st is float:
			sfrac = clampf(st as float, 0.0, 1.0)
	var k := 1.0 - exp(-10.0 * delta)
	_health_w = lerpf(_health_w, hfrac, k)
	_stamina_w = lerpf(_stamina_w, sfrac, k)
	var hw := RADAR_W * 0.58
	_health.size.x = maxf(hw * _health_w, 0.0)
	_health.color = C_HEALTH_LOW if hfrac < 0.3 else C_HEALTH
	_stamina.size.x = maxf((RADAR_W - hw - 6.0) * _stamina_w, 0.0)
	# In a car the stamina bar is meaningless; fade it rather than lie with a full bar.
	_stamina.modulate.a = 0.35 if not on_foot else 1.0


func _update_top_right() -> void:
	var police := _peer("police")
	var heat := 0
	if police != null:
		var hv: Variant = police.get("heat")
		if hv is int: heat = hv as int
	# While the police are searching (you are unseen) the lit stars blink at 2 Hz,
	# GTA's "they lost you" tell; police.search_active is the source of truth.
	var searching: bool = police != null and police.get("search_active") == true  # gotcha: `:=` cannot infer a get()==true
	var blink: bool = searching and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
	for i in _stars.size():
		var lit: bool = i < heat and not blink
		_stars[i].add_theme_color_override("font_color", C_STAR_ON if lit else C_STAR_OFF)
	var combat := _peer("combat")
	if combat != null:
		# combat.gd's public read API: current_weapon_data() carries "name"
		# (already upper-cased at load), current_ammo()/current_reserve() are
		# -1 for a melee slot, current_weapon_type() is "gun" or "melee".
		var nm := str(combat.get("current_weapon_id")).to_upper()
		if combat.has_method("current_weapon_data"):
			var wd: Variant = combat.call("current_weapon_data")
			if wd is Dictionary and (wd as Dictionary).has("name"):
				nm = str((wd as Dictionary)["name"])
		_weapon_lbl.text = nm
		var t := str(combat.call("current_weapon_type")) if combat.has_method("current_weapon_type") else "gun"
		var mag := int(combat.call("current_ammo")) if combat.has_method("current_ammo") else -1
		var res := int(combat.call("current_reserve")) if combat.has_method("current_reserve") else -1
		if t == "melee" or mag < 0:
			_ammo_lbl.text = ""
		else:
			_ammo_lbl.text = "%d | %s" % [mag, ("∞" if res < 0 else str(res))]
	var repo := _peer("repo_board")
	if repo != null:
		var m: Variant = repo.get("money")
		if m is int:
			_cash_lbl.text = "$%s" % _thousands(int(m))


func _update_bottom(delta: float, actor: Node3D, on_foot: bool) -> void:
	# Objective: exactly what repo_board computes, never a second opinion.
	var repo := _peer("repo_board")
	var obj := ""
	if repo != null:
		var jl: Variant = repo.get("_job_label")
		if jl is Label and is_instance_valid(jl):
			obj = (jl as Label).text
	_obj_lbl.text = obj
	# Scripted jobs already own their objective and exposure UI. Do not issue
	# an unrelated ambient repo order underneath them.
	for key in ["mission_hook_and_ladder", "mission_second_collection"]:
		var mission := _peer(key)
		if mission != null and int(mission.get("state")) != 0:
			_obj_lbl.text = ""
			break
	# Verb hint: mode-aware (D-033), shown for HINT_FADE_S after a mode change.
	var mode := 1 if on_foot else 0
	if mode != _last_on_foot:
		_last_on_foot = mode
		_hint_left = HINT_FADE_S
		_hint_lbl.text = _hint_text(on_foot)
	_hint_left = maxf(_hint_left - delta, 0.0)
	_hint_lbl.modulate.a = clampf(_hint_left / 1.0, 0.0, 1.0)
	# Interact prompt: a vehicle within reach on foot.
	var prompt := ""
	if on_foot and actor != null:
		var v := _nearest_vehicle(actor.global_position, PROMPT_RANGE)
		if v != null:
			var dn := str(v.get("display_name")) if "display_name" in v else "VEHICLE"
			prompt = "E — ENTER %s" % dn.to_upper()
	_prompt_lbl.text = prompt


func _hint_text(on_foot: bool) -> String:
	if on_foot:
		return "WASD move · SHIFT sprint · ALT walk · CTRL crouch · SPACE jump · RMB aim · LMB fire · Q weapon · R reload · V shoulder · E enter · G interact"
	return "WASD drive · SPACE handbrake · E exit · F hook · N radio · C camera · TAB own rig · BACKSPACE reset"


# ============================== RADAR ========================================
func _on_radar_draw() -> void:
	var actor := _actor()
	var focus := _flat(actor.global_position) if actor != null else Vector2.ZERO
	var s := (RADAR_W * 0.5) / RADAR_RANGE
	var c := Vector2(RADAR_W * 0.5, RADAR_H * 0.5)
	_radar.draw_rect(Rect2(0, 0, RADAR_W, RADAR_H), C_RADAR_BG, true)

	# --- District land tints (downtown slab field, Stonebridle plat).
	var dt_x0 := CITY.GRID_WEST
	var dt_z0 := CITY.GRID_NORTH
	var dt_x1 := dt_x0 + CITY.GRID_COLS * (CITY.BLOCK + CITY.STREET) - CITY.STREET
	var dt_z1 := dt_z0 + CITY.GRID_ROWS * (CITY.BLOCK + CITY.STREET) - CITY.STREET
	_quad(Vector2(dt_x0, dt_z0), Vector2(dt_x1, dt_z1), focus, s, c, C_RADAR_LAND)
	var sr: Rect2 = CITY.SUB_RECT
	_quad(sr.position, sr.end, focus, s, c, C_RADAR_LAND)

	# --- The Threefork floodway: dry drivable CONCRETE, not water (D-035).
	_quad(Vector2(CITY.CH_X0, CITY.CH_Z0), Vector2(CITY.CH_X1, 1400.0), focus, s, c, C_CONCRETE)

	# --- Downtown grid, drawn at true street width (26 m).
	var sw := maxf(CITY.STREET * s, 3.0)
	for xv: Variant in DRESS.NS_X:
		_seg(Vector2(float(xv), DRESS.NS_Z_RANGE.x), Vector2(float(xv), DRESS.NS_Z_RANGE.y), focus, s, c, C_ROAD, sw)
	for zv: Variant in DRESS.EW_Z:
		_seg(Vector2(DRESS.EW_X_RANGE.x, float(zv)), Vector2(DRESS.EW_X_RANGE.y, float(zv)), focus, s, c, C_ROAD, sw)
	# Hospital campus street south to County General, and the impound spur.
	_seg(Vector2(CITY.HOSPITAL_X, DRESS.NS_Z_RANGE.y), Vector2(CITY.HOSPITAL_X, 640.0), focus, s, c, C_ROAD_MINOR, sw * 0.6)
	# --- Freeway deck + frontage roads.
	_seg(Vector2(-CITY.FWY_HALF_LEN, 0), Vector2(CITY.FWY_HALF_LEN, 0), focus, s, c, C_FWY, maxf(CITY.FWY_HALF_W * 2.0 * s, 4.0))
	for side: float in [-1.0, 1.0]:
		_seg(Vector2(-CITY.FWY_HALF_LEN, side * CITY.FRONTAGE_Z), Vector2(CITY.FWY_HALF_LEN, side * CITY.FRONTAGE_Z), focus, s, c, C_ROAD_MINOR, maxf(12.0 * s, 2.0))

	# --- Wanted search radius (police publishes it when the player is out of sight).
	var police := _peer("police")
	if police != null:
		var sa: Variant = police.get("search_active")
		var sc: Variant = police.get("search_center")
		var srad: Variant = police.get("search_radius")
		if sa == true and sc is Vector3 and srad is float:
			var p := _to_map(_flat(sc as Vector3), focus, s, c)
			_radar.draw_circle(p, float(srad) * s, C_SEARCH)
			_radar.draw_arc(p, float(srad) * s, 0.0, TAU, 48, C_SEARCH_RIM, 2.0)

	# --- Fixed markers.
	_marker(Vector2(CITY.HOSPITAL_X, 612.0), focus, s, c, C_HOSPITAL, "H")
	_marker(Vector2(709.0, 558.0), focus, s, c, C_PAD, "P")
	if _peer("race_event") != null:
		_marker(Vector2(-620.0, 150.0), focus, s, c, Color(0.9, 0.9, 0.9), "R")

	# --- Blips.
	var on_foot := bool(main_ref.get("on_foot"))
	var own: Variant = main_ref.get("own_vehicle")
	if on_foot and own is Node3D and is_instance_valid(own) and (own as Node3D).is_inside_tree():
		var p := _to_map(_flat((own as Node3D).global_position), focus, s, c)
		_radar.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), C_TRUCK, true)
	for n: Node in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
			var cp := _to_map(_flat((n as Node3D).global_position), focus, s, c)
			_radar.draw_circle(cp, 4.0, C_COP_CAR)
			_radar.draw_arc(cp, 4.0, 0.0, TAU, 12, C_COP, 1.5)
	for n: Node in get_tree().get_nodes_in_group("officer"):
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
			_radar.draw_circle(_to_map(_flat((n as Node3D).global_position), focus, s, c), 2.5, C_COP)
	var repo := _peer("repo_board")
	if repo != null:
		var tgt: Variant = repo.get("_target")
		if tgt is Node3D and is_instance_valid(tgt) and (tgt as Node3D).is_inside_tree():
			var tp := _to_map(_flat((tgt as Node3D).global_position), focus, s, c)
			_radar.draw_circle(tp, 5.0, C_TARGET)
			_radar.draw_arc(tp, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.8), 1.5)

	# --- Player arrow, always centred, always pointing up (heading-up map).
	var session := _peer("session")
	if session != null:
		var route: PackedVector2Array = session.route
		for i in range(1, route.size()):
			_seg(route[i - 1], route[i], focus, s, c, C_TARGET, 4.0)
		var destination: Dictionary = session.navigation_target()
		if not destination.is_empty():
			var wp := _to_map(destination.pos, focus, s, c)
			var offset := wp - c
			# Off-screen destinations stay on the radar edge as a bearing.
			var edge := maxf(absf(offset.x) / (c.x - 14), absf(offset.y) / (c.y - 14))
			if edge > 1.0:
				wp = c + offset / edge
			_radar.draw_circle(wp, 6, C_TARGET)
			_radar.draw_arc(wp, 8, 0, TAU, 20, Color.WHITE, 1.5)

	var pts := PackedVector2Array([c + Vector2(0, -8), c + Vector2(5.5, 6), c + Vector2(0, 3), c + Vector2(-5.5, 6)])
	_radar.draw_colored_polygon(pts, C_PLAYER)
	_radar.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8), 1.5)
	# --- North tick on the rim.
	var nv := Vector2(0, -1).rotated(_rot)
	var rim := c + nv * Vector2(RADAR_W * 0.5 - 12.0, RADAR_H * 0.5 - 12.0)
	_radar.draw_string(_font_bold, rim + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_RIM)
	# --- Rim.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = C_RIM
	sb.set_corner_radius_all(int(RADAR_RADIUS))
	_radar.draw_style_box(sb, Rect2(0, 0, RADAR_W, RADAR_H))


# ============================== DRAW HELPERS =================================
func _to_map(world: Vector2, focus: Vector2, s: float, c: Vector2) -> Vector2:
	return (world - focus).rotated(_rot) * s + c


func _seg(wa: Vector2, wb: Vector2, focus: Vector2, s: float, c: Vector2, col: Color, width: float) -> void:
	var a := _to_map(wa, focus, s, c)
	var b := _to_map(wb, focus, s, c)
	# Cheap reject: both ends far outside the radar on the same side.
	var pad := width + 8.0
	if (a.x < -pad and b.x < -pad) or (a.x > RADAR_W + pad and b.x > RADAR_W + pad) \
			or (a.y < -pad and b.y < -pad) or (a.y > RADAR_H + pad and b.y > RADAR_H + pad):
		return
	_radar.draw_line(a, b, col, width)


## A world-axis-aligned rectangle, drawn as a rotated quad (heading-up map).
func _quad(w0: Vector2, w1: Vector2, focus: Vector2, s: float, c: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([
		_to_map(Vector2(w0.x, w0.y), focus, s, c), _to_map(Vector2(w1.x, w0.y), focus, s, c),
		_to_map(Vector2(w1.x, w1.y), focus, s, c), _to_map(Vector2(w0.x, w1.y), focus, s, c)])
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts: bb = bb.expand(p)
	if not bb.intersects(Rect2(-8, -8, RADAR_W + 16, RADAR_H + 16)):
		return
	_radar.draw_colored_polygon(pts, col)


func _marker(world: Vector2, focus: Vector2, s: float, c: Vector2, col: Color, glyph: String) -> void:
	var p := _to_map(world, focus, s, c)
	# Off-radar markers clamp to the rim so the player always knows which way.
	var inside := p.x > 10.0 and p.y > 10.0 and p.x < RADAR_W - 10.0 and p.y < RADAR_H - 10.0
	var q := p
	var alpha := 1.0
	if not inside:
		var d := p - c
		var half := Vector2(RADAR_W * 0.5 - 11.0, RADAR_H * 0.5 - 11.0)
		var t := minf(half.x / maxf(absf(d.x), 1e-3), half.y / maxf(absf(d.y), 1e-3))
		q = c + d * t
		alpha = 0.7
	var col_a := Color(col.r, col.g, col.b, col.a * alpha)
	_radar.draw_rect(Rect2(q - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.8 * alpha), true)
	_radar.draw_rect(Rect2(q - Vector2(6, 6), Vector2(12, 12)), col_a, true)
	_radar.draw_string(_font_bold, q + Vector2(-4.0, 4.5), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.95 * alpha))


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ============================== UI HELPERS ===================================
func _rect(parent: Control, col: Color, x: float, y_from_bottom: float, w: float, h: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	r.offset_left = x; r.offset_right = x + w
	r.offset_top = y_from_bottom; r.offset_bottom = y_from_bottom + h
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _label(text: String, size: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", C_OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(3, size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sys_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Helvetica Neue", "Helvetica", "Arial", "Liberation Sans", "sans-serif"])
	f.font_weight = weight
	return f


func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var k := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0: out = "," + out
	return ("-" if n < 0 else "") + out


# ============================== PLUMBING =====================================
func _actor() -> Node3D:
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node3D).is_inside_tree():
			return a as Node3D
	return null


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var v: Variant = (sys as Dictionary).get(peer_name)
		if v is Node and is_instance_valid(v):
			return v as Node
	return null


## Nearest enterable vehicle within `range` — a RigidBody3D driven by the
## raycast vehicle script (has set_external_input). Scanned only on foot.
func _nearest_vehicle(from: Vector3, range_m: float) -> Node3D:
	var best: Node3D = null
	var bd := range_m
	for n in main_ref.get_children():
		if n is RigidBody3D and is_instance_valid(n) and n.has_method("set_external_input"):
			var d := (n as Node3D).global_position.distance_to(from)
			if d < bd:
				bd = d; best = n as Node3D
	return best
