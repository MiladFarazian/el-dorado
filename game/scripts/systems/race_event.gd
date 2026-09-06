extends Node
## FLOODWAY SPRINT — the map's signature race: an out-and-back time trial down
## the Threefork floodway channel (greybox_city.gd digs it at x [-710,-530],
## z [100,1000], floor y=-6). Roll onto the start pad at the north mouth, hold
## HANDBRAKE for a second, beat the 3-2-1 countdown, thread 16 gates in strict
## order between the bridge columns, take air off two of the three hazard
## ramps, hairpin near the south wall, and bring it home. Pylons and beacons
## are PURELY VISUAL (no colliders) — clipping a gate can never wreck a run.
## Pays through repo_board.add_money (the one wallet). Police heat does NOT
## pause the race: cops in the channel mid-run is the good kind of chaos.
## Deterministic: zero RNG, fixed gate table, fixed-timestep race clock.

# ============================== TUNABLES =====================================
# Channel facts mirrored from scripts/world/greybox_city.gd: flat floor spans
# x [-685,-555] at y=-6; bridge columns (2 m square) at x -680/-620/-560 under
# decks at z=300 and z=650 (deck underside y=-1.14, so 2.2 m pylons fit under);
# jump ramps are 12 m wide with the launch edge at y=-2.6:
#   J1 x=-660 z=400 launches SOUTH; J2 x=-580 z=480 and J3 x=-620 z=560 NORTH.
const FLOOR_Y := -6.0
const PAD_CENTER := Vector3(-620.0, FLOOR_Y, 150.0)  # start/finish, north mouth
const PAD_RADIUS := 9.0              # XZ arming-zone radius (m)
const REARM_EXIT := 4.0              # leave pad by this extra margin to re-arm
const ARM_MAX_SPEED := 3.0           # m/s: roll on slower than this to arm
const HOLD_SECONDS := 1.0            # handbrake hold that triggers countdown
const COUNTDOWN_SECONDS := 3.0
const GATE_RADIUS := 10.0            # XZ pass radius, strict order
const GATE_HALF_WIDTH := 7.0         # pylon offset each side of gate centre
const PYLON_SIZE := Vector3(0.7, 2.2, 0.7)
# ── D-034: THE LAST VEIL ─────────────────────────────────────────────────────
# Until M23 the two gate markers were 34 m emissive BOXES at MIX alpha 0.4/0.25
# — the exact mechanism D-032 measured and D-033 fixed in beacon_kit.gd. MIX is
# `out = src*a + dst*(1-a)`: a covered pixel was 40 % replaced by cyan AND the
# background it replaced was crushed to 60 %. A light source cannot subtract
# light, so that was never a beacon, it was a sheet of coloured glass — and a
# box also has facets, corners and a hard silhouette, and had NO distance term,
# so its screen coverage grew as 1/d^2 exactly where the player needed it least.
# Migrated to the shared kit: additive blend, Y-billboarded soft-edged column
# with a ramp that dies below its own top, a ground corona for close range, and
# a Driver that fades the column out inside 26 m and boosts it 4.2x by 260 m.
# Register matches repo_board.gd so every "go here" marker in the game reads the
# same. The corona radius is GATE_HALF_WIDTH on purpose: the ring of light on
# the channel floor IS the gate mouth, which is a better close-range read than
# the old box ever was.
const BEAM_HEIGHT := 21.0
const BEAM_WIDTH := 2.6
const BEAM_ALPHA_A := 0.30; const BEAM_ENERGY_A := 1.30   # the NEXT gate
const BEAM_ALPHA_B := 0.20; const BEAM_ENERGY_B := 0.85   # the one after
const BEAM_RING := 7.0                                    # = GATE_HALF_WIDTH
const BEACON := preload("res://scripts/world/beacon_kit.gd")
const ABANDON_DISTANCE := 90.0       # base wander allowance from the next gate
const ABANDON_LEG_SLACK := 30.0      # legs longer than base allow leg + slack
const OUT_SECONDS := 6.0             # continuous out-of-channel limit
const CHANNEL := Rect2(-712.0, 98.0, 184.0, 904.0)  # channel footprint + 2 m
const OUT_ABOVE_Y := -0.5            # at/above grade counts as out (jump apex
                                     # is ~ +1.8 for only ~2 s — never trips 6 s)
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)  # protected: never build in
# Tier arithmetic (honest, from the course as built): summing the 17 legs of
# the gate table below (pad -> G1..G16 -> pad) gives ~1690 m.
#   GOLD   avg ~20 m/s (wrecker ~30 sustained on the long straights, ~18-22
#          threading bridge gaps and jump lineups, ~10-12 through the hairpin):
#          1690 / 20 ≈ 85 s
#   SILVER avg ~16 m/s (one big mistake or cautious lines): 1690 / 16 ≈ 106 s
#   BRONZE avg ~13 m/s (survived):                          1690 / 13 ≈ 130 s
const TIERS: Array = [[85.0, 600, "GOLD"], [106.0, 350, "SILVER"], [130.0, 150, "BRONZE"]]
# 16 gates, out-and-back down the channel floor. (x, z); y is always the floor.
const GATES: Array[Vector2] = [
	Vector2(-618, 220),  # 1  launch south off the pad
	Vector2(-652, 298),  # 2  thread bridge-1 west gap (columns -680/-620)
	Vector2(-660, 365),  # 3  line up dead centre on J1
	Vector2(-660, 434),  # 4  AIR GATE — 28 m past J1's launch edge (z=405.5)
	Vector2(-596, 512),  # 5  slot the gap between J2 (x-580) and J3 (x-620)
	Vector2(-588, 648),  # 6  thread bridge-2 east gap (columns -620/-560)
	Vector2(-655, 760),  # 7  long southwest sweep
	Vector2(-668, 862),  # 8  west lane — hairpin entry
	Vector2(-618, 952),  # 9  HAIRPIN apex, 45 m short of the south wall
	Vector2(-570, 852),  # 10 hairpin exit east — full channel width used
	Vector2(-586, 740),  # 11 east lane heading home
	Vector2(-590, 652),  # 12 re-thread bridge-2 east gap northbound
	Vector2(-619, 583),  # 13 line up on J3 (ramp base z=565.5)
	Vector2(-620, 524),  # 14 AIR GATE — 30 m past J3's launch edge (z=554.5)
	Vector2(-645, 420),  # 15 west lane, clear of J1's east flank
	Vector2(-651, 299),  # 16 re-thread bridge-1 west gap, then run to the pad
]
const HAZARD := Color(0.92, 0.45, 0.10)
const CYAN := Color(0.25, 0.95, 1.0)
const BLUE := Color(0.25, 0.45, 1.0)
const TIER_COLORS := {"GOLD": Color(1.0, 0.84, 0.25), "SILVER": Color(0.85, 0.88, 0.95),
	"BRONZE": Color(0.85, 0.55, 0.30), "FINISHED": Color(0.75, 0.75, 0.75)}
const RESULT_SECONDS := 4.0          # results flash fade time
const GO_SECONDS := 1.2              # "GO!" flash fade time

# ============================== STATE ========================================
enum { IDLE, COUNTDOWN, RUNNING }
var main_ref: Node = null
var _state := IDLE
var _hold_t := 0.0                   # handbrake-held accumulator on the pad
var _cd_t := 0.0                     # countdown remaining
var _race_t := 0.0                   # race clock (fixed timestep)
var _gate_idx := 0                   # next target; GATES.size() = finish pad
var _leg_start := PAD_CENTER         # previous target (for abandon allowance)
var _out_t := 0.0                    # continuous out-of-channel time
var _must_exit_pad := false          # finished/abandoned: leave pad to re-arm
var _on_pad := false
var _best := INF                     # session-best finish time
var _pulse_t := 0.0
var _beacon_a: Node3D = null          # cyan: the NEXT gate (beacon_kit Driver)
var _beacon_b: Node3D = null          # blue, dimmer: the gate after
var _ui: CanvasLayer = null
var _top: Label = null               # top-center y~130: timer + next-gate dist
var _center: Label = null            # countdown / GO / results
var _center_t := 0.0
var _center_fade := RESULT_SECONDS

func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false)
		return  # smoke gate: no course props, no processing, no UI
	_build_course()
	_build_ui()

# ============================== RACE LOGIC ===================================
func _physics_process(delta: float) -> void:
	if main_ref == null: return
	var pv := _player()
	if pv == null: return
	var pos := pv.global_position
	var pad_d := Vector2(pos.x - PAD_CENTER.x, pos.z - PAD_CENTER.z).length()
	match _state:
		IDLE: _tick_idle(delta, pv, pad_d)
		COUNTDOWN: _tick_countdown(delta)
		RUNNING: _tick_running(delta, pos)

func _tick_idle(delta: float, pv: RigidBody3D, pad_d: float) -> void:
	if _must_exit_pad:               # no instant restart while parked on the pad
		if pad_d > PAD_RADIUS + REARM_EXIT:
			_must_exit_pad = false
		return
	_on_pad = pad_d <= PAD_RADIUS and pv.linear_velocity.length() < ARM_MAX_SPEED
	if _on_pad and InputMap.has_action("handbrake") and Input.is_action_pressed("handbrake"):
		_hold_t += delta
		if _hold_t >= HOLD_SECONDS:
			_hold_t = 0.0
			_state = COUNTDOWN
			_cd_t = COUNTDOWN_SECONDS
			_set_beacons(0)
	else:
		_hold_t = 0.0

func _tick_countdown(delta: float) -> void:
	_cd_t -= delta                   # creeping before GO is legal; this is Texas
	if _cd_t <= 0.0:
		_state = RUNNING
		_race_t = 0.0; _gate_idx = 0; _out_t = 0.0; _leg_start = PAD_CENTER
		_flash_center("GO!", Color(0.5, 1.0, 0.5), GO_SECONDS)

func _tick_running(delta: float, pos: Vector3) -> void:
	_race_t += delta
	var target := _target_pos(_gate_idx)
	var d := Vector2(pos.x - target.x, pos.z - target.z).length()
	if d <= GATE_RADIUS:
		if _gate_idx >= GATES.size():
			_finish()
		else:
			_leg_start = target
			_gate_idx += 1
			_set_beacons(_gate_idx)
		return
	# Abandon 1: wandered off. Base allowance is 90 m from the next gate; legs
	# longer than that allow their own length + slack, otherwise merely starting
	# a 120 m leg (several exist on a 1.7 km / 16-gate course) would abandon.
	var leg := Vector2(target.x - _leg_start.x, target.z - _leg_start.z).length()
	if d > maxf(ABANDON_DISTANCE, leg + ABANDON_LEG_SLACK):
		_abandon()
		return
	# Abandon 2: out of the channel (past the rims / over the mouth bank / up at
	# grade) for OUT_SECONDS continuously. Jump air time (~2 s) never trips it.
	if not CHANNEL.has_point(Vector2(pos.x, pos.z)) or pos.y > OUT_ABOVE_Y:
		_out_t += delta
		if _out_t >= OUT_SECONDS:
			_abandon()
	else:
		_out_t = 0.0

func _finish() -> void:
	_state = IDLE
	_must_exit_pad = true
	_hide_beacons()
	var tier := "FINISHED"; var pay := 0
	for t: Array in TIERS:           # ordered fastest first
		if _race_t <= float(t[0]):
			tier = str(t[2]); pay = int(t[1])
			break
	if pay > 0:
		var rb := _peer("repo_board")
		if rb != null and rb.has_method("add_money"):
			rb.call("add_money", pay, "SPRINT %s" % tier)
	var msg := "FLOODWAY SPRINT — %s  %s" % [tier, _fmt(_race_t)]
	if _race_t < _best:
		if _best < INF:
			msg += "\nNEW BEST"
		_best = _race_t
	_flash_center(msg, TIER_COLORS.get(tier, Color.WHITE), RESULT_SECONDS)

func _abandon() -> void:
	_state = IDLE
	_must_exit_pad = true            # timer clears; pad re-arms once you return
	_hold_t = 0.0; _out_t = 0.0
	_hide_beacons()
	_flash_center("RACE ABANDONED", Color(1.0, 0.4, 0.3), RESULT_SECONDS)

func _target_pos(idx: int) -> Vector3:
	if idx >= GATES.size(): return PAD_CENTER
	return Vector3(GATES[idx].x, FLOOR_Y, GATES[idx].y)

func _player() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null

# ============================== COURSE BUILD =================================
func _build_course() -> void:
	# Start/finish pad: purely visual slab + stripes + two tall entry pylons
	# (no colliders — nothing on this course can snag a bumper).
	_visual_box(Vector3(18, 0.08, 10), PAD_CENTER + Vector3(0, 0.06, 0), Color(0.24, 0.24, 0.27), false)
	for sz: float in [-1.0, 1.0]:
		_visual_box(Vector3(18, 0.06, 0.7), PAD_CENTER + Vector3(0, 0.1, sz * 4.6), HAZARD, true)
		_visual_box(Vector3(0.8, 3.6, 0.8), PAD_CENTER + Vector3(sz * 9.0, 1.8, 0), HAZARD, true)
	# Gate pylons: each pair sits perpendicular to its incoming leg so gates
	# face the racing line. Short enough (2.2 m) to fit under the bridge decks.
	var prev := PAD_CENTER
	for i in GATES.size():
		var g := _target_pos(i)
		var dir := (g - prev) * Vector3(1, 0, 1)
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
		var across := Vector3(-dir.z, 0.0, dir.x) * GATE_HALF_WIDTH
		for s: float in [-1.0, 1.0]:
			_visual_box(PYLON_SIZE, g + across * s + Vector3(0, PYLON_SIZE.y * 0.5, 0), HAZARD, true)
		prev = g
	_beacon_a = _make_beam(CYAN, BEAM_ALPHA_A, BEAM_ENERGY_A)
	_beacon_b = _make_beam(BLUE, BEAM_ALPHA_B, BEAM_ENERGY_B)
	_hide_beacons()


## One gate marker, in the shared objective-beacon look (D-033). The origin of
## the returned node is the GROUND point being marked, so `_set_beacons` does no
## half-height bookkeeping — which is also why the old `lift` vector is gone.
func _make_beam(color: Color, alpha: float, energy: float) -> Node3D:
	var n: Node3D = BEACON.beacon(color, BEAM_HEIGHT, BEAM_WIDTH, alpha, energy,
		BEAM_RING)
	n.visible = false
	add_child(n)
	return n

## Pure visual box (MeshInstance3D, NO collider). Formally refuses to build
## inside the protected corridor — the floodway is nowhere near it, but the
## contract check stays load-bearing if anyone retunes the course.
func _visual_box(size: Vector3, pos: Vector3, color: Color, emissive: bool,
		alpha := 1.0) -> MeshInstance3D:
	if CORRIDOR.has_point(Vector2(pos.x, pos.z)):
		push_warning("race_event: refused to build inside protected corridor at %v" % pos)
		return null
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size; mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha); m.roughness = 0.8
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = 1.6
	mi.material_override = m
	mi.position = pos                # Node3D under a plain Node: acts as global
	add_child(mi)
	return mi

func _set_beacons(next_idx: int) -> void:
	if _beacon_a != null:
		_beacon_a.visible = true
		_beacon_a.position = _target_pos(next_idx)
	if _beacon_b != null:
		_beacon_b.visible = next_idx + 1 <= GATES.size()
		if _beacon_b.visible:
			_beacon_b.position = _target_pos(next_idx + 1)

func _hide_beacons() -> void:
	if _beacon_a != null: _beacon_a.visible = false
	if _beacon_b != null: _beacon_b.visible = false

# ============================== UI ===========================================
func _process(delta: float) -> void:
	_pulse_t += delta
	# The 6 Hz emission pulse that used to live here is GONE, deliberately. The
	# kit's Driver owns `emission_energy_multiplier` now (it writes the
	# distance-driven gain into it every frame), so a second writer would fight
	# it — and a 6 Hz flicker on an ADDITIVE column is exactly the screen-space
	# attention-grab D-032/D-033 spent two cycles removing. What tells the two
	# gates apart is what always should have: colour (CYAN next, BLUE after),
	# energy (1.30 vs 0.85), the ground corona under the live one, and the HUD
	# line below, which prints the gate number and a live metre count.
	if _ui == null:
		return
	match _state:
		RUNNING:
			var label := "GATE %d/%d" % [_gate_idx + 1, GATES.size()] \
				if _gate_idx < GATES.size() else "FINISH"
			var dist := 0
			var pv := _player()
			if pv != null:
				var t := _target_pos(_gate_idx)
				dist = int(Vector2(pv.global_position.x - t.x, pv.global_position.z - t.z).length())
			_top.text = "%s   %s  %dm" % [_fmt(_race_t), label, dist]
			_top.visible = true
		COUNTDOWN:
			_top.text = "FLOODWAY SPRINT"
			_top.visible = true
			_center.text = str(ceili(_cd_t))
			_center.add_theme_color_override("font_color", HAZARD)
			_center.modulate.a = 1.0
			_center.visible = true
		IDLE:
			_top.visible = _on_pad and not _must_exit_pad
			if _top.visible:
				_top.text = "FLOODWAY SPRINT — starting..." if _hold_t > 0.0 \
					else "FLOODWAY SPRINT — hold HANDBRAKE to start"
	if _state != COUNTDOWN and _center_t > 0.0:
		_center_t = maxf(0.0, _center_t - delta)
		_center.modulate.a = clampf(_center_t / (_center_fade * 0.4), 0.0, 1.0)
		if _center_t <= 0.0:
			_center.visible = false

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 8                    # between repo panel (5) and police HUD (12)
	add_child(_ui)
	_top = Label.new()               # assigned slot: top-center, y ~130
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 130)
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top.add_theme_font_size_override("font_size", 26)
	_top.add_theme_color_override("font_color", CYAN)
	_top.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_top.add_theme_constant_override("outline_size", 7)
	_top.visible = false
	_ui.add_child(_top)
	_center = Label.new()            # countdown numbers / GO! / results, brief
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 56)
	_center.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_center.add_theme_constant_override("outline_size", 10)
	_center.visible = false
	_ui.add_child(_center)

func _flash_center(text: String, color: Color, secs: float) -> void:
	if _center == null: return
	_center.text = text
	_center.add_theme_color_override("font_color", color)
	_center.modulate.a = 1.0
	_center.visible = true
	_center_t = secs; _center_fade = secs

func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]  # live m:ss.cs
