extends Node
## COMBAT v2 (M16) — THE WEAPON INVENTORY. Hitscan from the camera centre, a
## spread-cone accuracy model whose crosshair never lies, camera recoil, aim
## assist (snap + sticky), drive-bys — now with an ordered slot inventory whose
## entire character lives in DATA (`res://data/weapons/*.json`), not here.
##
## Slots come from the JSONs' `slot` field: 0 FISTS, 1 SNUB PISTOL, 2 PUMP
## SHOTGUN, 3 STREET SMG, 4 BAT. Q ("weapon_next") cycles. You start on the
## pistol, so every pre-M16 behaviour is exactly what it was.
##
## ============================ MELEE CONTRACT ================================
## PUBLIC to melee.gd (Fighting agent) — poll null-safely, this system may be
## absent in a partial tree:
##
##     combat.get("current_weapon_id") -> String   # "fists" | "bat" | "pistol"...
##     combat.weapon_changed(id: String)           # signal, emitted on every switch
##     combat.current_weapon_type() -> String      # "gun" | "melee"
##     combat.is_melee_selected() -> bool          # the one-call version
##
## WHEN THE CURRENT WEAPON IS type "melee" (fists.json, bat.json, anything with
## `"type": "melee"`), combat guarantees, every tick:
##   * it reads NEITHER "fire" NOR "aim" — LMB/RMB are untouched and belong
##     entirely to melee.gd, on foot AND behind the wheel (no melee drive-bys);
##   * no gun rig exists on the character (the old one is freed on the switch);
##   * `is_aiming` is false, so the camera never zooms and player_character
##     never enters the shooter stance;
##   * the combat_speed_cap meta is removed (melee owns its own stride);
##   * `aim_friction` is written back to 1.0 on the camera, so a sticky-aim
##     multiplier can never survive a switch and slow melee mouse look;
##   * the reticle is hidden (the ring is a gun's cone — it would be a lie),
##     while the bottom-left band keeps showing the weapon name and health.
## melee.gd owns reach/damage/swing_interval/knockdown in those files; combat
## reads only id/name/type/slot from a melee entry.
## ============================================================================
##
## All FX built in code at setup (zero per-shot allocation). Active ONLY while
## main.on_foot; drive-by behind the wheel for weapons flagged `driveby`.
## ENTIRELY INERT in smoke mode.

signal shot_fired(pos: Vector3)
signal weapon_changed(id: String)     # MELEE CONTRACT: fires on every switch

# ============================== TUNABLES =====================================
# Per-weapon numbers are NOT here — they are in res://data/weapons/*.json.
# What lives here is what belongs to the SHOOTER rather than to the gun.
const RNG_SEED := 0xBA9C; const MIX_RATE := 22050
const WEAPON_DIR := "res://data/weapons"
const FIRE_RANGE := 140.0            # reach (m), shared by every hitscan weapon
# --- Accuracy model. Spread is a CONE HALF-ANGLE in radians: every pellet is
# perturbed inside it, and the crosshair ring is drawn from the SAME number,
# so what you see is literally what the gun will do. Stance/bloom/recoil are
# per weapon; the movement penalty and the crouch bonus are the player's.
const SPREAD_MOVE := 0.045           # added at full sprint
const AIM_MOVE_FACTOR := 0.35        # aimed walking barely opens the cone
const CROUCH_SPREAD_MULT := 0.7      # M16: crouch steadies EVERY weapon...
const CROUCH_META := "is_crouched"   # ...published by the movement system
const SPREAD_TO_PX := 2100.0         # spread radians -> crosshair ring pixels
const RING_MIN_PX := 6.0
# M16: was 120 px, which quietly capped the ring at 0.057 rad while the pistol
# alone can reach 0.162 (hip + sprint + full bloom) — the HUD was lying at the
# exact moment the lie mattered most. 345 px covers every weapon's true worst
# case (pistol 340, SMG 307, shotgun 231) and still fits a 900 px viewport.
const RING_MAX_PX := 345.0
const BLOOM_RECOVER_IDLE := 0.11     # rad/s bled off while holding a melee slot
# --- Aim assist. Pressing RMB snaps the rig onto the best target near the view
# centre; a target near the reticle also slows the mouse (sticky aim). LIVE FOR
# EVERY GUN — no weapon opts out.
const SNAP_RANGE := 55.0             # m: acquisition reach on the aim press
const SNAP_CONE := 0.13              # rad (~7.5 deg) half-angle around the view
const STICKY_CONE := 0.045           # rad (~2.6 deg): mouse slows over a target
const STICKY_FRICTION := 0.55        # camera sens multiplier inside that cone
# --- Damage model.
const HEAD_LOCAL_Y := 0.52           # metres above a ped's centre origin
# --- Feedback.
const HITMARK_TIME := 0.16; const HITMARK_KILL_TIME := 0.3
const CASING_POOL := 10; const CASING_TIME := 1.1
# --- Switching.
const SWITCH_TIME := 0.35            # s of draw before the new weapon can fire
# ---- M23 WEAPON WHEEL ---------------------------------------------------------
const WHEEL_HOLD := 0.22             # s of Q held before the wheel opens (a tap cycles)
const WHEEL_TIME_SCALE := 0.3        # GTA slows the world while you choose
const WHEEL_R_IN := 74.0             # px inner radius
const WHEEL_R_OUT := 190.0           # px outer radius
const WHEEL_DEAD := 18.0             # px of mouse travel before a sector is picked
const WHEEL_BG := Color(0.04, 0.04, 0.05, 0.62)
const WHEEL_SEC := Color(0.16, 0.16, 0.18, 0.85)
const WHEEL_HOT := Color(0.85, 0.72, 0.30, 0.92)
const WHEEL_RIM := Color(0.92, 0.92, 0.92, 0.55)
const SWITCH_PITCH := 0.9            # the click of a gun coming up
# --- Drive-by (per-weapon interval/spread/permission live in the JSONs).
const DRIVEBY_MIN_ARC := 0.15        # can't shoot through your own hood
const AIM_WALK_CAP := 3.0                 # m/s; on-foot controller reads the meta
const SPEED_CAP_META := "combat_speed_cap"
const PED_IMPULSE := 220.0; const PED_POP := 90.0  # carry + up-fling (N*s)
const PED_HEAT := 1; const PED_RESPECT := -3       # shooting people is bad
const PED_CHARGE_META := "combat_ped_charged"      # once per ped, ever
const POLICE_HP := 60                     # 5 pistol rounds cripple a cruiser
const POLICE_HP_META := "combat_hp"; const CRIPPLED_META := "combat_crippled"
# foot_cops counts HITS, not hp (HITS_TO_DOWN = 2 pistol body hits). M16 keeps
# that contract honest across a mixed inventory by banking damage per officer
# and spending it one pistol-round at a time: 12 damage == one "hit". A pistol
# inside falloff_start pays exactly 1 hit per round (identical to M15); an SMG
# needs 4 rounds, three shotgun pellets are 2 hits and drop him.
const OFFICER_HIT_DAMAGE := 12.0
const OFFICER_DMG_META := "combat_officer_dmg"
const VEHICLE_IMPULSE := 900.0            # cars rock on their springs when shot
const SHOT_HEAT_RADIUS := 45.0; const SHOT_HEAT_WINDOW := 8.0  # witness heat
const FLASH_TIME := 0.05; const TRACER_TIME := 0.03
const PUFF_POOL := 8; const PUFF_TIME := 0.15      # pooled: >= shotgun pellets
const PUFF_SCALE := Vector2(0.12, 0.6)             # puff box scale start -> end
const AUDIO_POOL := 3                     # overlapping gunshots on the actor
const CLICK_DB := -12.0
const SHOT_UNIT_SIZE := 14.0; const SHOT_MAX_DIST := 160.0
const RING_REST := 14.0; const RING_START := 26.0  # aim ring settles inward
const RING_RATE := 60.0; const RING_KICK := 7.0    # px/s tighten; recoil bump
const HEALTH_W := 190.0                   # HUD band y[-196,-166]; debug HUD ~-158
const RIG_POS := Vector3(0.28, 0.45, -0.22)        # right hand height (fwd -Z)

# ============================== STATE ========================================
var is_aiming := false                    # public: on-foot controller caps speed
## MELEE CONTRACT: the id of the selected weapon, e.g. "fists". Never null.
var current_weapon_id := ""
var main_ref: Node = null
var _weapons: Array[Dictionary] = []      # slot-ordered, loaded from JSON
var _mags := PackedInt32Array()           # per-slot rounds in the gun
var _reserves := PackedInt32Array()       # per-slot spare rounds (-1 = infinite)
var _slot := 0
var _rng := RandomNumberGenerator.new()
var _fire_cd := 0.0; var _reload_t := 0.0; var _heat_window := 0.0
var _mid_total := 0; var _mid_left := 0   # reload choreography (shell-by-shell)
var _rig: Node3D = null                   # weapon boxes, child of the character
var _rig_id := ""                         # which weapon the rig was built for
var _muzzle_fwd := 0.2                    # m ahead of the hand the flash sits
var _flash_root: Node3D = null; var _flash_t := 0.0
var _tracer: MeshInstance3D = null; var _tracer_t := 0.0
var _puffs: Array[MeshInstance3D] = []; var _puff_t := PackedFloat32Array()
var _puff_i := 0; var _pool_i := 0
var _shot_stream: AudioStreamWAV = null; var _click_stream: AudioStreamWAV = null
var _shot_streams: Dictionary = {}        # sound id -> AudioStreamWAV
var _players: Array[AudioStreamPlayer3D] = []
var _ui: CanvasLayer = null; var _ammo: Label = null
var _cross: Control = null                # hidden while a melee slot is up
var _wheel: Control = null                 # M23: the radial weapon wheel
var _wheel_open := false
var _wheel_hold := 0.0
var _wheel_vec := Vector2.ZERO             # accumulated mouse travel while open
var _wheel_pick := -1                      # highlighted slot, -1 = keep current
var _health_fill: ColorRect = null; var _ticks: Array[ColorRect] = []
var _band: Control = null                  # M23: the health/ammo band, yields to hud_gta
var _ring_r := RING_REST
var _bloom := 0.0                         # current added spread (radians)
var _hitmark_t := 0.0; var _hitmark_kill := false
var _marks: Array[ColorRect] = []
var _dot: ColorRect = null                # crosshair centre, flips red on target
var _on_target := false                   # centre ray currently on flesh/police
var _casings: Array[MeshInstance3D] = []; var _casing_t := PackedFloat32Array()
var _casing_vel: Array[Vector3] = []; var _casing_i := 0

func setup(main: Node) -> void:
	main_ref = main
	# Data first, gate second: melee.gd polls current_weapon_id and deserves a
	# real answer even in a smoke build. Reading five JSONs draws no RNG,
	# spawns nothing, and touches no physics.
	_load_weapons()
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return  # smoke gate: inert
	_rng.seed = RNG_SEED
	# Build order is load-bearing: the pistol shot and the click are synthesised
	# from the same RNG state as every milestone before this one, so they are
	# byte-identical. New weapons append AFTER them.
	_shot_stream = _build_gunshot(); _click_stream = _build_click()
	_shot_streams["pistol"] = _shot_stream
	_shot_streams["shotgun"] = _build_shotgun_shot()
	_shot_streams["smg"] = _build_smg_shot()
	_build_fx(); _build_ui()

# ============================== INVENTORY ====================================
## Weapons are whatever is on disk. Order is the `slot` field (ties broken by
## id so the list is deterministic); an unslotted file lands at the back. A
## missing or malformed file is skipped, and an empty directory still leaves a
## working pistol — the same defensive-loading contract main.gd uses.
func _load_weapons() -> void:
	var paths: Array[String] = []
	var dir := DirAccess.open(WEAPON_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".json"):
				paths.append(WEAPON_DIR + "/" + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	paths.sort()
	for p in paths:
		var w := _read_weapon(p)
		if not w.is_empty():
			_weapons.append(w)
	_weapons.sort_custom(_slot_before)
	if _weapons.is_empty():
		_weapons.append(_default_pistol())
	_mags.resize(_weapons.size()); _reserves.resize(_weapons.size())
	for i in _weapons.size():
		_mags[i] = int(_weapons[i].get("mag", 0))
		_reserves[i] = int(_weapons[i].get("reserve", -1))
	_slot = 0
	for i in _weapons.size():  # you start armed with the pistol, as ever
		if String(_weapons[i].get("id", "")) == "pistol":
			_slot = i; break
	current_weapon_id = String(_weapons[_slot].get("id", ""))


func _slot_before(a: Dictionary, b: Dictionary) -> bool:
	var sa := int(a.get("slot", 99)); var sb := int(b.get("slot", 99))
	if sa != sb: return sa < sb
	return String(a.get("id", "")) < String(b.get("id", ""))


## Parse + normalise one weapon file. Everything gets a default, so a JSON
## missing a field is playable rather than fatal. A melee entry keeps only the
## four fields combat needs — melee.gd reads the rest of that file itself.
func _read_weapon(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty(): return {}
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary): return {}
	var d := parsed as Dictionary
	var id := String(d.get("id", path.get_file().get_basename()))
	var w: Dictionary = {
		"id": id,
		"name": String(d.get("name", id)).to_upper(),
		"type": String(d.get("type", "gun")),
		"slot": int(d.get("slot", 99)),
	}
	if String(w["type"]) == "melee":
		return w
	w["fire_interval"] = maxf(float(d.get("fire_interval", 0.18)), 0.02)
	w["auto"] = bool(d.get("auto", false))
	w["pellets"] = maxi(int(d.get("pellets", 1)), 1)
	w["spread_aim"] = maxf(float(d.get("spread_base_aim", 0.004)), 0.0)
	w["spread_hip"] = maxf(float(d.get("spread_base_hip", 0.042)), 0.0)
	w["bloom"] = maxf(float(d.get("bloom", 0.010)), 0.0)
	w["bloom_max"] = maxf(float(d.get("bloom_max", 0.075)), 0.0)
	w["bloom_recover"] = maxf(float(d.get("bloom_recover", 0.11)), 0.0)
	w["recoil_pitch"] = float(d.get("recoil_pitch", 0.020))
	w["recoil_yaw"] = float(d.get("recoil_yaw", 0.008))
	w["trauma"] = float(d.get("trauma", 0.13))
	w["damage"] = maxf(float(d.get("damage", 12)), 0.0)
	w["impulse_mult"] = maxf(float(d.get("impulse_mult", 1.0)), 0.0)
	w["falloff_start"] = maxf(float(d.get("falloff_start", 45.0)), 0.0)
	w["falloff_end"] = maxf(float(d.get("falloff_end", 130.0)),
		float(w["falloff_start"]) + 0.001)
	w["falloff_min"] = clampf(float(d.get("falloff_min", 0.35)), 0.0, 1.0)
	w["headshot_mult"] = maxf(float(d.get("headshot_mult", 3.0)), 1.0)
	w["mag"] = maxi(int(d.get("mag", 12)), 1)
	w["reserve"] = int(d.get("reserve", -1))
	w["reload_time"] = maxf(float(d.get("reload_time", 1.3)), 0.05)
	w["reload_clicks"] = maxi(int(d.get("reload_clicks", 2)), 2)
	w["driveby"] = bool(d.get("driveby", true))
	w["driveby_interval"] = maxf(float(d.get("driveby_interval", 0.26)), 0.02)
	w["driveby_spread"] = maxf(float(d.get("driveby_spread", 0.075)), 0.0)
	w["sound"] = String(d.get("sound", "pistol"))
	w["sound_db"] = float(d.get("sound_db", -6.0))
	return w


## Last-ditch weapon so a tree with no data directory still shoots. Keys here
## are the NORMALISED ones _read_weapon() produces, not the JSON spellings.
func _default_pistol() -> Dictionary:
	return {
		"id": "pistol", "name": "SNUB PISTOL", "type": "gun", "slot": 1,
		"fire_interval": 0.18, "auto": false, "pellets": 1,
		"spread_aim": 0.004, "spread_hip": 0.042,
		"bloom": 0.010, "bloom_max": 0.075, "bloom_recover": 0.11,
		"recoil_pitch": 0.020, "recoil_yaw": 0.008, "trauma": 0.13,
		"damage": 12.0, "impulse_mult": 1.0,
		"falloff_start": 45.0, "falloff_end": 130.0, "falloff_min": 0.35,
		"headshot_mult": 3.0, "mag": 12, "reserve": -1,
		"reload_time": 1.3, "reload_clicks": 2,
		"driveby": true, "driveby_interval": 0.26, "driveby_spread": 0.075,
		"sound": "pistol", "sound_db": -6.0,
	}


func _weapon() -> Dictionary:
	if _slot < 0 or _slot >= _weapons.size(): return {}
	return _weapons[_slot]


func _is_melee(w: Dictionary) -> bool:
	return String(w.get("type", "gun")) == "melee"


# --- MELEE CONTRACT surface ---------------------------------------------------
## "gun" or "melee" for the selected slot. Safe before setup() (returns "gun").
func current_weapon_type() -> String:
	var w := _weapon()
	return String(w.get("type", "gun")) if not w.is_empty() else "gun"

## True while combat is passing LMB/RMB through to melee.gd.
func is_melee_selected() -> bool:
	return _is_melee(_weapon())

## Read-only copy of the selected weapon's data (melee.gd may want reach etc.).
func current_weapon_data() -> Dictionary:
	return _weapon().duplicate(true)

## Rounds in the gun right now; -1 for a melee slot.
func current_ammo() -> int:
	if is_melee_selected(): return -1
	return _mags[_slot] if _slot < _mags.size() else 0

## Spare rounds; -1 means infinite (v1: everything is infinite).
func current_reserve() -> int:
	return _reserves[_slot] if _slot < _reserves.size() else -1

## The ordered slot list, ids only — for HUDs, wheels and harnesses.
func weapon_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for w in _weapons: out.append(String(w.get("id", "")))
	return out

## Select by id. Returns false if that weapon is not in the inventory.
func select_weapon(id: String) -> bool:
	for i in _weapons.size():
		if String(_weapons[i].get("id", "")) == id:
			_select(i); return true
	return false
# ------------------------------------------------------------------------------


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_heat_window = maxf(_heat_window - delta, 0.0)
	var w := _weapon()
	var recover := float(w.get("bloom_recover", BLOOM_RECOVER_IDLE))
	_bloom = maxf(_bloom - recover * delta, 0.0)
	_handle_switch()
	w = _weapon()  # the switch may have changed it
	var ch := _character()
	if main_ref == null or not bool(main_ref.get("on_foot")) or ch == null:
		is_aiming = false
		_drive_by(delta, w)   # behind the wheel some guns still work, worse
		return  # holstered on foot: the reload timer freezes with us
	var hp: Variant = ch.get("health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		is_aiming = false
		if ch.has_meta(SPEED_CAP_META): ch.remove_meta(SPEED_CAP_META)
		if _rig != null and is_instance_valid(_rig): _rig.visible = false
		return  # the dead don't aim through the funeral card
	_ensure_audio(ch)
	if _is_melee(w):
		# MELEE CONTRACT: not one line below this reads "fire" or "aim".
		is_aiming = false
		if ch.has_meta(SPEED_CAP_META): ch.remove_meta(SPEED_CAP_META)
		_drop_rig()
		_on_target = false
		var cam := _camera()
		if cam != null: cam.set("aim_friction", 1.0)  # never leave sticky aim on
		return
	_ensure_rig(ch)
	var was_aiming := is_aiming
	is_aiming = Input.is_action_pressed("aim")
	if is_aiming and not was_aiming:
		_ring_r = RING_START  # ring blooms open
		_aim_snap(ch)         # the press acquires the target under the view
	_update_assist(ch)        # sticky-aim friction + reticle-on-target truth
	if is_aiming:
		ch.set_meta(SPEED_CAP_META, AIM_WALK_CAP)  # controller caps walk speed
	elif ch.has_meta(SPEED_CAP_META):
		ch.remove_meta(SPEED_CAP_META)
	if _rig != null and is_instance_valid(_rig): _rig.visible = is_aiming
	if _reload_t > 0.0:
		_tick_reload(delta, w)
	elif Input.is_action_just_pressed("reload") and _mags[_slot] < int(w["mag"]):
		_start_reload(w)
	# Auto weapons fire on HOLD; semi-autos on the press edge only. The dry
	# click is edge-only either way, or an empty SMG becomes a castanet.
	var just := Input.is_action_just_pressed("fire")
	var want := just or (bool(w["auto"]) and Input.is_action_pressed("fire"))
	if want:
		if _reload_t > 0.0 or _mags[_slot] <= 0:
			if just: _play(_click_stream, CLICK_DB, 1.35)  # dry click
		elif _fire_cd <= 0.0:
			_fire(ch, w)


func _process(delta: float) -> void:
	_flash_t -= delta
	if _flash_root != null: _flash_root.visible = _flash_t > 0.0
	_tracer_t -= delta
	if _tracer != null: _tracer.visible = _tracer_t > 0.0
	for i in _puffs.size():
		if _puff_t[i] <= 0.0: continue
		_puff_t[i] -= delta
		var k := 1.0 - clampf(_puff_t[i] / PUFF_TIME, 0.0, 1.0)
		_puffs[i].scale = Vector3.ONE * lerpf(PUFF_SCALE.x, PUFF_SCALE.y, k)
		if _puff_t[i] <= 0.0: _puffs[i].visible = false
	_step_casings(delta)
	_hitmark_t = maxf(_hitmark_t - delta, 0.0)
	_update_ui(delta)


# ============================== SWITCHING ====================================
## Q cycles the inventory, on foot AND behind the wheel (you pick your drive-by
## gun the same way you pick your walking one). Never through the funeral card.
func _handle_switch() -> void:
	if not InputMap.has_action("weapon_next"): return
	var ch := _character()
	if ch != null:
		var hp: Variant = ch.get("health")
		if (hp is float or hp is int) and float(hp) <= 0.0:
			_wheel_close(false); return
	# HOLD opens the wheel; RELEASE selects (or cycles, if it was only a tap).
	if Input.is_action_pressed("weapon_next"):
		# _handle_switch runs in _physics_process; the fixed step is in game time,
		# so divide by time_scale to count REAL seconds once the world has slowed.
		_wheel_hold += get_physics_process_delta_time() / maxf(Engine.time_scale, 0.05)
		if not _wheel_open and _wheel_hold >= WHEEL_HOLD and _weapons.size() >= 2:
			_wheel_open_now()
		return
	if _wheel_hold > 0.0:
		if _wheel_open:
			_wheel_close(true)
		else:
			_cycle_weapon(1)
		_wheel_hold = 0.0


func _wheel_open_now() -> void:
	if _ui == null or not _ui.visible:
		return  # holstered (in a car without a drive-by weapon): no wheel, no slow-mo
	_wheel_open = true
	_wheel_vec = Vector2.ZERO
	_wheel_pick = -1
	Engine.time_scale = WHEEL_TIME_SCALE
	if _wheel != null:
		_wheel.visible = true
		_wheel.queue_redraw()


func _wheel_close(select: bool) -> void:
	if not _wheel_open:
		return
	_wheel_open = false
	Engine.time_scale = 1.0
	if _wheel != null:
		_wheel.visible = false
	if select and _wheel_pick >= 0 and _wheel_pick < _weapons.size():
		_select(_wheel_pick)


## Mouse travel steers the pick while the wheel is open; the event is consumed
## so the camera's _unhandled_input never turns the view under the wheel.
func _input(event: InputEvent) -> void:
	if not _wheel_open:
		return
	if event is InputEventMouseMotion:
		_wheel_vec += (event as InputEventMouseMotion).relative
		if _wheel_vec.length() > WHEEL_DEAD:
			var n := _weapons.size()
			var a := fmod(_wheel_vec.angle() + PI * 0.5 + TAU + PI / float(n), TAU)
			_wheel_pick = int(a / (TAU / float(n))) % n
			if _wheel != null:
				_wheel.queue_redraw()
		get_viewport().set_input_as_handled()


func _wheel_draw() -> void:
	var c := _wheel.size * 0.5
	var n := _weapons.size()
	if n == 0:
		return
	_wheel.draw_circle(c, WHEEL_R_OUT + 6.0, WHEEL_BG)
	var step := TAU / float(n)
	for i in n:
		var a0 := -PI * 0.5 + step * float(i) - step * 0.5
		var pts := PackedVector2Array()
		var segs := 14
		for k in segs + 1:
			pts.append(c + Vector2.from_angle(a0 + step * float(k) / float(segs)) * WHEEL_R_OUT)
		for k in range(segs, -1, -1):
			pts.append(c + Vector2.from_angle(a0 + step * float(k) / float(segs)) * WHEEL_R_IN)
		var hot := i == _wheel_pick or (_wheel_pick < 0 and i == _slot)
		_wheel.draw_colored_polygon(pts, WHEEL_HOT if hot else WHEEL_SEC)
		_wheel.draw_polyline(pts, WHEEL_RIM, 1.5)
		var mid := c + Vector2.from_angle(a0 + step * 0.5) * ((WHEEL_R_IN + WHEEL_R_OUT) * 0.5)
		var w: Dictionary = _weapons[i]
		var nm := str(w.get("name", w.get("id", "")))
		var ammo := "" if _is_melee(w) else "%d" % (_mags[i] if i < _mags.size() else 0)
		var col := Color(0.08, 0.07, 0.05) if hot else Color(0.95, 0.95, 0.95)
		var f := ThemeDB.fallback_font
		_wheel.draw_string(f, mid + Vector2(-f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x * 0.5, -2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		if ammo != "":
			_wheel.draw_string(f, mid + Vector2(-f.get_string_size(ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, 14), ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	_wheel.draw_circle(c, WHEEL_R_IN - 8.0, WHEEL_BG)
	var cur := str(_weapons[_slot].get("name", "")) if _slot < n else ""
	var f2 := ThemeDB.fallback_font
	_wheel.draw_string(f2, c + Vector2(-f2.get_string_size(cur, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, 5), cur, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHEEL_RIM)


func _cycle_weapon(step: int) -> void:
	if _weapons.size() < 2: return
	_select(wrapi(_slot + step, 0, _weapons.size()))


## The switching state machine. A switch always: cancels the reload (you do not
## get to finish it in the other hand), clears bloom (a fresh gun is a fresh
## cone), costs SWITCH_TIME of draw before it can fire, drops the old rig, and
## clears aim state so no shooter-stance/sticky-aim residue survives.
func _select(idx: int) -> void:
	if idx < 0 or idx >= _weapons.size() or idx == _slot: return
	_slot = idx
	_reload_t = 0.0; _mid_left = 0; _mid_total = 0
	_bloom = 0.0
	_fire_cd = maxf(_fire_cd, SWITCH_TIME)
	_ring_r = RING_START
	is_aiming = false
	var ch := _character()
	if ch != null and ch.has_meta(SPEED_CAP_META): ch.remove_meta(SPEED_CAP_META)
	var cam := _camera()
	if cam != null: cam.set("aim_friction", 1.0)
	_on_target = false
	_drop_rig()
	current_weapon_id = String(_weapons[_slot].get("id", ""))
	_play(_click_stream, CLICK_DB, SWITCH_PITCH)
	weapon_changed.emit(current_weapon_id)


# ============================== FIRING =======================================
## Total cone half-angle right now: stance + movement + accumulated bloom,
## steadied by a crouch. The crosshair is drawn from this exact number.
## Aimed movement barely opens the cone — walking a bead onto someone is
## supposed to work.
func _spread(ch: Node3D) -> float:
	var w := _weapon()
	if w.is_empty() or _is_melee(w): return 0.0
	var base := float(w["spread_aim"]) if is_aiming else float(w["spread_hip"])
	var sp := 0.0
	var v: Variant = ch.get("velocity")
	if v is Vector3:
		sp = Vector3((v as Vector3).x, 0.0, (v as Vector3).z).length()
	var move := SPREAD_MOVE * (AIM_MOVE_FACTOR if is_aiming else 1.0)
	var total := base + move * clampf(sp / 7.0, 0.0, 1.0) + _bloom
	# M16: crouching steadies the whole cone, not just the stance term — and
	# the ring shrinks with it, because the ring IS this number.
	if _crouched(ch): total *= CROUCH_SPREAD_MULT
	return total


## The movement system publishes this meta; absent means standing.
func _crouched(ch: Node3D) -> bool:
	return ch != null and is_instance_valid(ch) and ch.has_meta(CROUCH_META) \
		and bool(ch.get_meta(CROUCH_META))


# ============================== AIM ASSIST ===================================
## The RMB press acquires the best target near the view centre — smallest
## angle off the camera forward inside SNAP_CONE and SNAP_RANGE, with line of
## sight — and points the rig straight at its chest. Free aim alone made this
## feel like GTA III; the snap is the GTA V half of the deal. Every gun gets
## it: there is no weapon-specific opt-out.
func _aim_snap(ch: Node3D) -> void:
	var cam := _camera()
	if cam == null: return
	var t := _best_target(cam, ch, SNAP_CONE, true)
	if t == null: return
	var chest := _target_chest(t)
	# The centre ray passes through the aim pivot (chest height + the rig's
	# lateral shoulder offset). The offset depends on the yaw being solved
	# for, so: solve flat, re-derive the shoulder, solve once more.
	var base: Vector3 = ch.global_position + Vector3.UP * 1.55
	var yaw := 0.0; var pitch := 0.0
	for _i in 2:
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var d := chest - (base + right * 0.55)
		yaw = atan2(-d.x, -d.z)
		pitch = atan2(d.y, maxf(Vector2(d.x, d.z).length(), 0.001))
	if cam.has_method("aim_snap"):
		cam.call("aim_snap", yaw, pitch)


## Per-tick assist state: sticky-aim friction for the camera (mouse slows over
## a target while aiming) and the reticle-on-target flag for the crosshair.
func _update_assist(ch: Node3D) -> void:
	var cam := _camera()
	if cam == null: return
	var f := 1.0
	if is_aiming and _best_target(cam, ch, STICKY_CONE, false) != null:
		f = STICKY_FRICTION
	cam.set("aim_friction", f)
	_on_target = false
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var t0 := maxf((ch.global_position + Vector3.UP * 1.4 - from).dot(dir), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from + dir * t0, from + dir * FIRE_RANGE)
	if ch is CollisionObject3D:
		q.exclude = [(ch as CollisionObject3D).get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Variant = hit["collider"]
		if col is Node and ((col as Node).is_in_group("pedestrian") \
				or (col as Node).is_in_group("police") \
				or (col as Node).is_in_group("officer")):
			_on_target = true


## Smallest-angle live target off the camera forward, or null. Knocked-down
## pedestrians (origin dropped to the floor) are skipped — no snapping onto
## bodies. LOS is a straight chest ray excluding shooter and target.
func _best_target(cam: Camera3D, ch: Node3D, cone: float, need_los: bool) -> Node3D:
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best: Node3D = null
	var best_ang := cone
	for grp: String in ["pedestrian", "officer", "police"]:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if not (n is Node3D): continue
			if not is_instance_valid(n): continue
			var t := n as Node3D
			if not t.is_inside_tree(): continue
			if grp != "police" and t.global_position.y < 0.55:
				continue  # down on the floor: not a snap target
			var chest := _target_chest(t)
			var to := chest - from
			var dist := to.length()
			if dist > SNAP_RANGE or dist < 2.0: continue
			var ang := fwd.angle_to(to)
			if ang >= best_ang: continue
			if need_los and not _clear_los(cam, ch, t, chest): continue
			best_ang = ang; best = t
	return best


func _target_chest(t: Node3D) -> Vector3:
	# Ped origin is the body centre; cruisers ride a little above the chassis.
	return t.global_position + Vector3.UP * (0.55 if t.is_in_group("police") else 0.25)


func _clear_los(cam: Camera3D, ch: Node3D, t: Node3D, chest: Vector3) -> bool:
	var world := cam.get_world_3d()
	if world == null: return true
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest)
	var ex: Array[RID] = []
	if ch is CollisionObject3D: ex.append((ch as CollisionObject3D).get_rid())
	if t is CollisionObject3D: ex.append((t as CollisionObject3D).get_rid())
	q.exclude = ex
	return world.direct_space_state.intersect_ray(q).is_empty()


## Perturb a direction inside a cone of half-angle `spread` (uniform on the
## disc, so shots cluster toward the middle the way a real group does).
func _scatter(dir: Vector3, spread: float) -> Vector3:
	if spread <= 0.0001:
		return dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var truly_up := right.cross(dir).normalized()
	var ang := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf()) * spread
	return (dir + (right * cos(ang) + truly_up * sin(ang)) * tan(r)).normalized()


## ONE trigger pull. A single-pellet gun is the M13 shot verbatim; a shotgun is
## the same code seven times over, each pellet independently scattered inside
## the LIVE cone and resolved as its own ray for its own share of the damage —
## so a half-in-cover target takes half a blast. FX (flash, casing, sound,
## recoil, heat) fire ONCE per pull, not once per pellet.
func _fire(ch: Node3D, w: Dictionary) -> void:
	var cam := _camera()
	if cam == null: return
	_mags[_slot] -= 1
	_fire_cd = float(w["fire_interval"])
	var pellets := int(w["pellets"])
	var per := float(w["damage"]) / float(pellets)
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var aim := cam.project_ray_normal(center)
	var spread := _spread(ch)
	var space := cam.get_world_3d().direct_space_state
	var lead := from + aim * FIRE_RANGE
	for p in pellets:
		var dir := _scatter(aim, spread)
		# Start the ray at the character's plane along the aim line, so the
		# camera-to-character stretch (the truck you just stepped out of, a wall
		# behind you) can never eat the shot.
		var t0 := maxf((ch.global_position + Vector3.UP * 1.4 - from).dot(dir), 0.0)
		var query := PhysicsRayQueryParameters3D.create(from + dir * t0, from + dir * FIRE_RANGE)
		if ch is CollisionObject3D:
			query.exclude = [(ch as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		var end := from + dir * FIRE_RANGE
		if not hit.is_empty():
			end = hit["position"]
			var col: Variant = hit["collider"]
			if col is Node: _resolve_hit(col as Node, end, dir, ch, from.distance_to(end), per, w)
			_spawn_puff(end)
		if p == 0: lead = end  # the tracer rides the first pellet
	var muzzle := _muzzle_pos(ch)
	_show_flash(muzzle); _show_tracer(muzzle, lead)
	_play(_shot_for(w), float(w["sound_db"]), _rng.randf_range(0.94, 1.06))
	_eject_casing(ch)
	_kick(w)
	_ring_r += RING_KICK; shot_fired.emit(muzzle); _witness_heat(ch)
	if _mags[_slot] <= 0: _start_reload(w)


## Muzzle climb, camera shake, and bloom — the three things that make a gun
## feel like it went off, and the three that give each gun its signature.
## Recoil moves the CAMERA, so it genuinely spoils the next shot instead of
## being decoration; orbit_yaw (the movement basis) is never touched.
func _kick(w: Dictionary) -> void:
	_bloom = minf(_bloom + float(w["bloom"]), float(w["bloom_max"]))
	var cam := _camera()
	if cam == null: return
	if cam.has_method("add_recoil"):
		cam.call("add_recoil", float(w["recoil_pitch"]) * _rng.randf_range(0.8, 1.2),
			float(w["recoil_yaw"]) * _rng.randf_range(-1.0, 1.0))
	if cam.has_method("add_trauma"):
		cam.call("add_trauma", float(w["trauma"]))


## DRIVE-BY: one hand on the wheel. Only weapons flagged `driveby` in data
## qualify — the pistol and the SMG, because you can hold them out a window in
## one hand. A pump shotgun needs the hand you are steering with, and a bat
## through the driver's window is melee.gd's business, not a hitscan. Slower
## and far less accurate than shooting on foot, no aim mode, and it will not
## fire through your own hood.
func _drive_by(delta: float, w: Dictionary) -> void:
	var veh := _fetch("vehicle")
	var cam := _camera()
	if veh == null or cam == null or main_ref == null:
		return
	if bool(main_ref.get("on_foot")):
		return
	# The audio pool rides the ACTOR, and behind the wheel that is the car —
	# bind it before any weapon check so a switch still clicks. (Pre-M16 the
	# pool stayed parented to the character that enter-vehicle had already
	# freed, which is why drive-by gunfire used to be silent.)
	_ensure_audio(veh)
	if w.is_empty() or _is_melee(w): return  # MELEE CONTRACT: LMB untouched
	if _reload_t > 0.0:
		_tick_reload(delta, w)
		return
	if not bool(w["driveby"]):
		return
	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload") \
			and _mags[_slot] < int(w["mag"]) and not Input.is_action_pressed("accelerate"):
		_start_reload(w)
		return
	if not InputMap.has_action("fire"):
		return
	var just := Input.is_action_just_pressed("fire")
	if not (just or (bool(w["auto"]) and Input.is_action_pressed("fire"))):
		return
	if _mags[_slot] <= 0:
		if just: _play(_click_stream, CLICK_DB, 1.35)
		return
	if _fire_cd > 0.0:
		return
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var aim := cam.project_ray_normal(center)
	var nose := -veh.global_transform.basis.z
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	if flat.dot(Vector3(nose.x, 0.0, nose.z).normalized()) > 1.0 - DRIVEBY_MIN_ARC:
		return  # dead ahead: that is your own hood
	_mags[_slot] -= 1; _fire_cd = float(w["driveby_interval"])
	var pellets := int(w["pellets"])
	var per := float(w["damage"]) / float(pellets)
	var spread := float(w["driveby_spread"]) + _bloom
	# Start clear of the car so the shot never hits the door you are behind.
	var muzzle := veh.global_position + Vector3.UP * 0.55 + flat * 1.9
	var space := cam.get_world_3d().direct_space_state
	var lead := muzzle + aim * FIRE_RANGE
	for p in pellets:
		var dir := _scatter(aim, spread)
		var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * FIRE_RANGE)
		query.exclude = [(veh as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		var end := muzzle + dir * FIRE_RANGE
		if not hit.is_empty():
			end = hit["position"]
			var col: Variant = hit["collider"]
			if col is Node: _resolve_hit(col as Node, end, dir, veh, muzzle.distance_to(end), per, w)
			_spawn_puff(end)
		if p == 0: lead = end
	_show_flash(muzzle); _show_tracer(muzzle, lead)
	_play(_shot_for(w), float(w["sound_db"]), _rng.randf_range(0.94, 1.06))
	_kick(w)
	shot_fired.emit(muzzle); _witness_heat(veh)
	if _mags[_slot] <= 0: _start_reload(w)


## Priority: pedestrian mannequin > foot officer > police cruiser > any rigid
## body > world (StaticBody: the impact puff, already spawned by the caller, is
## the answer). `dist` drives per-weapon damage falloff; a hit high on a body
## counts as a head shot. `dmg` is THIS pellet's share of the trigger pull.
func _resolve_hit(body: Node, pos: Vector3, dir: Vector3, ch: Node3D, dist: float,
		dmg: float, w: Dictionary) -> void:
	if not (body is RigidBody3D) or not is_instance_valid(body):
		return
	var rb := body as RigidBody3D
	var head := pos.y - rb.global_position.y > HEAD_LOCAL_Y
	var mult := _falloff(dist, w) * (float(w["headshot_mult"]) if head else 1.0)
	var imp := float(w["impulse_mult"])
	if rb.is_in_group("pedestrian"):
		_hit_ped(rb, pos, dir, ch, head, imp)
		_hitmark(true)
	elif rb.is_in_group("officer"):  # foot cops own their hit logic
		_hit_officer(rb, pos, dir, head, dmg * mult, imp)
		_hitmark(true)
	elif rb.is_in_group("police"):
		_hit_police(rb, pos, dir, dmg * mult, imp)
		_hitmark(false)
	else:  # civilian / towable / player vehicle / street prop / debris
		if rb.freeze:
			var inter := _peer("interactables")  # shot hydrants geyser too
			if inter != null and inter.has_method("prop_shot"):
				inter.call("prop_shot", rb)
			if rb.freeze: rb.freeze = false  # not a street prop: parked traffic wakes
		rb.apply_impulse(dir * VEHICLE_IMPULSE * imp, pos - rb.global_position)
		_hitmark(false)


## Rounds lose bite downrange, on each weapon's own curve — a pistol out to
## 130 m, a shotgun that is basically a rumour past 30.
func _falloff(dist: float, w: Dictionary) -> float:
	var start := float(w["falloff_start"])
	if dist <= start:
		return 1.0
	var t := clampf((dist - start) / (float(w["falloff_end"]) - start), 0.0, 1.0)
	return lerpf(1.0, float(w["falloff_min"]), t)


## Hand the ped to its own knockdown state machine (so pedestrians.gd stops
## kinematic path placement and owns the get-up), then add directional carry.
## Heat + Respect land ONCE per ped via meta — the ped system's own vehicular
## charge only fires for striker == player vehicle, so no double-charging.
func _hit_ped(ped: RigidBody3D, pos: Vector3, dir: Vector3, ch: Node3D, head: bool,
		imp: float) -> void:
	var peds := _peer("pedestrians")
	if peds != null and peds.has_method("force_knockdown"):
		peds.call("force_knockdown", ped, ch)  # flips WALK -> DOWN, unfreezes
	if ped.freeze: ped.freeze = false
	var boost := 1.6 if head else 1.0
	ped.apply_impulse(dir * PED_IMPULSE * imp * boost + Vector3.UP * PED_POP * imp,
		pos - ped.global_position)
	if ped.has_meta(PED_CHARGE_META): return
	ped.set_meta(PED_CHARGE_META, true); _add_heat(PED_HEAT)
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_respect"):
		repo.call("add_respect", PED_RESPECT, "")


## foot_cops.officer_shot() counts HITS, so a mixed inventory has to convert.
## Damage banks on the officer and is spent one OFFICER_HIT_DAMAGE at a time;
## a head hit still drops him outright (that contract is foot_cops', not ours).
## A pistol inside its falloff start pays exactly 1.0 hits per round, which is
## the M15 behaviour to the bit — and foot cops hold at 9 m, so no live fight
## is ever outside it.
func _hit_officer(rb: RigidBody3D, pos: Vector3, dir: Vector3, head: bool,
		dmg: float, imp: float) -> void:
	var fc := _peer("foot_cops")
	if fc != null and fc.has_method("officer_shot"):
		if head:
			fc.call("officer_shot", rb, true)
			if rb.has_meta(OFFICER_DMG_META): rb.remove_meta(OFFICER_DMG_META)
		else:
			var acc := float(rb.get_meta(OFFICER_DMG_META, 0.0)) + dmg
			var guard := 0
			while acc >= OFFICER_HIT_DAMAGE and guard < 16:
				acc -= OFFICER_HIT_DAMAGE; guard += 1
				fc.call("officer_shot", rb, false)
			rb.set_meta(OFFICER_DMG_META, acc)
	rb.apply_impulse(dir * PED_IMPULSE * imp, pos - rb.global_position)


## Cruiser hp lives in meta (police.gd owns the node's lifecycle, not us).
## At 0: CRIPPLED — full brake + handbrake once, marked so heat never re-charges.
func _hit_police(cruiser: RigidBody3D, pos: Vector3, dir: Vector3, dmg: float,
		imp: float) -> void:
	var hp := int(cruiser.get_meta(POLICE_HP_META, POLICE_HP)) - int(dmg)
	cruiser.set_meta(POLICE_HP_META, hp)
	if hp <= 0 and not cruiser.has_meta(CRIPPLED_META):
		cruiser.set_meta(CRIPPLED_META, true); _add_heat(1)
		_hitmark(true)
		if cruiser.has_method("set_external_input"):
			cruiser.call("set_external_input", 0.0, 1.0, 0.0, true)
	cruiser.apply_impulse(dir * VEHICLE_IMPULSE * imp, pos - cruiser.global_position)


## Crosshair confirmation. `decisive` marks a knockdown or a crippled cruiser —
## it flashes longer and hotter than a plain connect.
func _hitmark(decisive: bool) -> void:
	if decisive or _hitmark_t <= 0.0 or not _hitmark_kill:
		_hitmark_t = HITMARK_KILL_TIME if decisive else HITMARK_TIME
		_hitmark_kill = decisive


## Gunfire with witnesses in earshot draws heat, at most once per 8 s window.
func _witness_heat(ch: Node3D) -> void:
	if _heat_window > 0.0: return
	for g: String in ["pedestrian", "police"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D and is_instance_valid(n) and (n as Node3D) \
					.global_position.distance_to(ch.global_position) <= SHOT_HEAT_RADIUS:
				_heat_window = SHOT_HEAT_WINDOW; _add_heat(1); return


# ============================== RELOAD =======================================
## Reload choreography is data: `reload_clicks` is the TOTAL number of
## mechanical sounds across `reload_time`, first and last included. A pistol
## (2) drops the mag and seats a fresh one. A pump shotgun (5) thumbs three
## shells in between. The last click is always the low "clack" of the weapon
## coming back up.
func _start_reload(w: Dictionary) -> void:
	if w.is_empty() or _is_melee(w): return
	if _mags[_slot] >= int(w["mag"]): return
	if _reserves[_slot] == 0: return  # dry: nothing left to feed it
	_reload_t = float(w["reload_time"])
	_mid_total = maxi(int(w["reload_clicks"]) - 2, 0)
	_mid_left = _mid_total
	_play(_click_stream, CLICK_DB, 1.0)  # the "click" drops the mag


func _tick_reload(delta: float, w: Dictionary) -> void:
	_reload_t -= delta
	if _reload_t > 0.0:
		if _mid_left > 0:
			var gap := float(w["reload_time"]) / float(_mid_total + 1)
			if _reload_t <= gap * float(_mid_left):
				_mid_left -= 1
				_play(_click_stream, CLICK_DB, 1.18)  # a shell goes in
		return
	_reload_t = 0.0; _mid_left = 0
	var cap := int(w["mag"])
	if _reserves[_slot] < 0:
		_mags[_slot] = cap                      # v1: every reserve is infinite
	else:
		var take := mini(cap - _mags[_slot], _reserves[_slot])
		_mags[_slot] += take
		_reserves[_slot] -= take
	_play(_click_stream, CLICK_DB, 0.75)        # the "clack" seats it


# ============================== FX ===========================================
func _build_fx() -> void:
	_flash_root = Node3D.new()  # Node3D under a plain Node: transform is global
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5); light.light_energy = 3.0
	light.omni_range = 5.0; light.shadow_enabled = false
	_flash_root.add_child(light)
	_flash_root.add_child(_box_mesh(Vector3(0.14, 0.14, 0.2), _emissive(Color(1.0, 0.9, 0.45))))
	_flash_root.visible = false
	add_child(_flash_root)
	_tracer = _box_mesh(Vector3(0.03, 0.03, 1.0), _emissive(Color(1.0, 0.8, 0.4)))
	_tracer.visible = false
	add_child(_tracer)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.62, 0.22); brass.metallic = 0.85; brass.roughness = 0.3
	_casing_t.resize(CASING_POOL)
	for i in CASING_POOL:
		var c := _box_mesh(Vector3(0.022, 0.022, 0.052), brass)
		c.visible = false
		add_child(c); _casings.append(c); _casing_t[i] = 0.0
		_casing_vel.append(Vector3.ZERO)
	var puff_mat := _emissive(Color(0.85, 0.8, 0.7))
	_puff_t.resize(PUFF_POOL)
	for i in PUFF_POOL:  # scale animates each puff's size
		var p := _box_mesh(Vector3.ONE, puff_mat)
		p.visible = false
		add_child(p); _puffs.append(p); _puff_t[i] = 0.0

func _show_flash(muzzle: Vector3) -> void:
	_flash_root.global_position = muzzle; _flash_root.visible = true; _flash_t = FLASH_TIME

func _show_tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from; var len := d.length()
	if len < 0.2: return
	var n := d / len
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var b := Basis.looking_at(n, up) * Basis.from_scale(Vector3(1.0, 1.0, len))
	_tracer.global_transform = Transform3D(b, from + d * 0.5)
	_tracer.visible = true; _tracer_t = TRACER_TIME

## Brass out the ejection port: a right-and-up toss with gravity. Not physics
## bodies — ten pooled boxes on a ballistic arc, so a firefight costs nothing.
func _eject_casing(ch: Node3D) -> void:
	if _casings.is_empty(): return
	var idx := _casing_i
	_casing_i = (_casing_i + 1) % CASING_POOL
	var b := ch.global_transform.basis
	_casings[idx].global_position = _muzzle_pos(ch) - b.z * -0.12 + b.x * 0.1
	_casings[idx].visible = true
	_casing_t[idx] = CASING_TIME
	_casing_vel[idx] = b.x * _rng.randf_range(1.4, 2.2) \
		+ Vector3.UP * _rng.randf_range(1.6, 2.4) - b.z * _rng.randf_range(-0.4, 0.4)


func _step_casings(delta: float) -> void:
	for i in _casings.size():
		if _casing_t[i] <= 0.0: continue
		_casing_t[i] -= delta
		_casing_vel[i] += Vector3.DOWN * 9.8 * delta
		_casings[i].global_position += _casing_vel[i] * delta
		_casings[i].rotate_x(12.0 * delta)
		_casings[i].rotate_y(7.0 * delta)
		if _casing_t[i] <= 0.0: _casings[i].visible = false


func _spawn_puff(pos: Vector3) -> void:
	var idx := -1
	for i in PUFF_POOL:  # prefer an idle slot; else steal round-robin
		if _puff_t[i] <= 0.0: idx = i; break
	if idx < 0:
		idx = _puff_i; _puff_i = (_puff_i + 1) % PUFF_POOL
	var p := _puffs[idx]
	p.global_position = pos; p.scale = Vector3.ONE * PUFF_SCALE.x
	p.visible = true; _puff_t[idx] = PUFF_TIME

func _emissive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.emission_enabled = true; m.emission = col
	m.emission_energy_multiplier = 2.5
	return m

func _box_mesh(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat
	return mi

# ============================== THE VISIBLE GUN ==============================
## Greybox weapon on the character's right side, silhouette-first: the pistol
## is a slide and a grip, the shotgun is long with a pump slab under the
## barrel, the SMG is a boxy receiver with a stick mag hanging out of it. You
## should be able to tell them apart from behind, at speed, in one frame.
## Rebuilt on a switch and recreated lazily — the character is freed on
## enter-vehicle and the rig dies with it. Melee slots get NO rig at all.
func _ensure_rig(ch: Node3D) -> void:
	var w := _weapon()
	if _is_melee(w):
		_drop_rig(); return
	var id := String(w.get("id", ""))
	if _rig != null and is_instance_valid(_rig) and _rig.get_parent() == ch \
			and _rig_id == id:
		return
	_drop_rig()
	_rig = Node3D.new()
	_rig.name = "WeaponRig"; _rig.position = RIG_POS
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.14, 0.16); mat.roughness = 0.4
	match id:
		"shotgun": _build_shotgun_rig(mat)
		"smg": _build_smg_rig(mat)
		_: _build_pistol_rig(mat)
	_rig_id = id
	_rig.visible = false; ch.add_child(_rig)


func _drop_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.visible = false  # queue_free is deferred: hide it THIS frame, or a
		_rig.queue_free()     # switch made while aiming shows two guns for a tick
	_rig = null; _rig_id = ""


func _rig_box(size: Vector3, at: Vector3, mat: StandardMaterial3D) -> void:
	var b := _box_mesh(size, mat)
	b.position = at
	_rig.add_child(b)


func _build_pistol_rig(mat: StandardMaterial3D) -> void:
	_rig_box(Vector3(0.05, 0.05, 0.18), Vector3.ZERO, mat)         # slide
	_rig_box(Vector3(0.04, 0.09, 0.05), Vector3(0.0, -0.06, 0.06), mat)  # grip
	_muzzle_fwd = 0.2


func _build_shotgun_rig(mat: StandardMaterial3D) -> void:
	_rig_box(Vector3(0.052, 0.056, 0.60), Vector3(0.0, 0.0, -0.16), mat)   # barrel
	_rig_box(Vector3(0.066, 0.052, 0.15), Vector3(0.0, -0.048, -0.20), mat) # pump
	_rig_box(Vector3(0.062, 0.080, 0.22), Vector3(0.0, -0.010, 0.10), mat)  # receiver
	_rig_box(Vector3(0.048, 0.070, 0.22), Vector3(0.0, -0.040, 0.30), mat)  # stock
	_muzzle_fwd = 0.46


func _build_smg_rig(mat: StandardMaterial3D) -> void:
	_rig_box(Vector3(0.076, 0.086, 0.26), Vector3(0.0, 0.0, -0.02), mat)   # receiver
	_rig_box(Vector3(0.034, 0.034, 0.14), Vector3(0.0, 0.006, -0.21), mat) # barrel
	_rig_box(Vector3(0.036, 0.160, 0.055), Vector3(0.0, -0.11, 0.01), mat) # stick mag
	_rig_box(Vector3(0.040, 0.085, 0.05), Vector3(0.0, -0.055, 0.10), mat) # grip
	_muzzle_fwd = 0.30


func _muzzle_pos(ch: Node3D) -> Vector3:
	if _rig != null and is_instance_valid(_rig) and _rig.is_inside_tree():
		return _rig.global_position - ch.global_transform.basis.z * _muzzle_fwd
	return ch.global_position + Vector3.UP * 0.45

# ============================== AUDIO ========================================
## Pooled players ride the ACTOR — the character on foot, the car during a
## drive-by (they die with whichever it is, so we re-check each tick).
## tree_exiting stop + _exit_tree stop: no 4.7.1 quit leak.
func _ensure_audio(host: Node3D) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if not _players.is_empty() and is_instance_valid(_players[0]) \
			and _players[0].get_parent() == host: return
	_players.clear()
	for i in AUDIO_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = SHOT_UNIT_SIZE; p.max_distance = SHOT_MAX_DIST
		p.tree_exiting.connect(p.stop); host.add_child(p); _players.append(p)

func _play(stream: AudioStreamWAV, db: float, pitch: float) -> void:
	if stream == null or _players.is_empty(): return
	var p := _players[_pool_i]
	_pool_i = (_pool_i + 1) % _players.size()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree(): return
	p.stream = stream; p.volume_db = db; p.pitch_scale = pitch; p.play()

func _shot_for(w: Dictionary) -> AudioStreamWAV:
	var s: Variant = _shot_streams.get(String(w.get("sound", "pistol")))
	return s if s is AudioStreamWAV else _shot_stream

func _exit_tree() -> void:
	for p in _players:
		if p != null and is_instance_valid(p): p.stop()

## PISTOL ~0.25 s: high noise crack decaying fast over a 140->55 Hz sine thump.
## Unchanged since M11 — and synthesised first, from the same RNG state, so it
## is byte-for-byte the gunshot the game has always had.
func _build_gunshot() -> AudioStreamWAV:
	var samples := PackedFloat32Array(); samples.resize(5512)
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-90.0 * t) * 0.85
		phase += TAU * lerpf(140.0, 55.0, clampf(t / 0.25, 0.0, 1.0)) / float(MIX_RATE)
		var thump := sin(phase) * exp(-14.0 * t) * 0.7
		samples[i] = (crack + thump) * minf(float(i) / 8.0, 1.0)  # ramp kills pop
	return _wav(samples)

## SHOTGUN ~0.42 s: a LAYERED low boom. The crack is run through a one-pole
## low-pass so it thuds instead of snapping, over TWO detuned sine bodies
## (105->42 Hz and 64->27 Hz) with a long decay — the beat between them is what
## makes it read as a big bore rather than a loud pistol. A short bright rattle
## on top is the shell and the action.
func _build_shotgun_shot() -> AudioStreamWAV:
	var samples := PackedFloat32Array(); samples.resize(9260)
	var p1 := 0.0; var p2 := 0.0; var lp := 0.0
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var raw := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.35)
		var blast := lp * exp(-26.0 * t) * 1.5
		p1 += TAU * lerpf(105.0, 42.0, clampf(t / 0.42, 0.0, 1.0)) / float(MIX_RATE)
		p2 += TAU * lerpf(64.0, 27.0, clampf(t / 0.42, 0.0, 1.0)) / float(MIX_RATE)
		var body := (sin(p1) * 0.62 + sin(p2) * 0.45) * exp(-7.0 * t)
		var rattle := raw * exp(-170.0 * t) * 0.25
		samples[i] = (blast + body + rattle) * 0.85 * minf(float(i) / 8.0, 1.0)
	return _wav(samples)

## SMG ~0.13 s: shorter and brighter than the pistol. The noise is
## high-passed by first difference (+6 dB/oct) so it snaps, the body sits an
## octave up (230->120 Hz) and decays nearly three times faster. At 11 rounds a
## second it has to leave room for the next one.
func _build_smg_shot() -> AudioStreamWAV:
	var samples := PackedFloat32Array(); samples.resize(2870)
	var phase := 0.0; var prev := 0.0
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var raw := _rng.randf_range(-1.0, 1.0)
		var hp := raw - prev; prev = raw
		var crack := hp * exp(-150.0 * t) * 0.45
		phase += TAU * lerpf(230.0, 120.0, clampf(t / 0.13, 0.0, 1.0)) / float(MIX_RATE)
		var thump := sin(phase) * exp(-38.0 * t) * 0.45
		samples[i] = (crack + thump) * minf(float(i) / 6.0, 1.0)
	return _wav(samples)

## Short mechanical tick — dry-fire plays it high, reload click/clack lower,
## shells mid, a weapon switch just under unity.
func _build_click() -> AudioStreamWAV:
	var samples := PackedFloat32Array(); samples.resize(1102)
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var s := _rng.randf_range(-1.0, 1.0) * exp(-220.0 * t) * 0.5 \
			+ sin(TAU * 2200.0 * t) * exp(-120.0 * t) * 0.4
		samples[i] = s * minf(float(i) / 6.0, 1.0)
	return _wav(samples)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray(); bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE; w.stereo = false; w.data = bytes
	return w

# ============================== UI ===========================================
## Crosshair centre dot + 4 aim ticks; weapon name + ammo + thin health bar
## bottom-left in the y[-196,-166] band (debug HUD cheat sheet tops out ~-158,
## minimap owns y[-380,-220]). All of it is hidden while driving; the reticle
## alone is hidden when a melee slot is up. Never built in smoke mode.
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 11  # debug HUD 10, police stars 12
	_ui.visible = false
	add_child(_ui)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_cross)
	# EVERY control here is MOUSE_FILTER_IGNORE — a captured mouse is pinned at
	# the exact screen centre, i.e. ON the crosshair dot, and a default-STOP
	# ColorRect there consumes every InputEventMouseMotion before the camera's
	# _unhandled_input ever runs. This single default made on-foot mouse look
	# dead in live play while every headless harness passed (they inject
	# actions, not GUI-routed motion). parent IGNORE does NOT propagate.
	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.9); _dot.position = Vector2(-2, -2); _dot.size = Vector2(4, 4)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.add_child(_dot)
	for i in 4:
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.75); tick.visible = false
		tick.size = Vector2(2, 8) if i < 2 else Vector2(8, 2)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(tick); _ticks.append(tick)
	for i in 4:  # hitmarker: four diagonal ticks that flash on a connect
		var mk := ColorRect.new()
		mk.visible = false
		mk.size = Vector2(9, 2)
		mk.pivot_offset = Vector2(4.5, 1)
		mk.rotation = deg_to_rad(45.0 if i % 2 == 0 else -45.0)
		mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(mk); _marks.append(mk)
	var band := Control.new()
	band.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	band.offset_left = 14; band.offset_right = 254
	band.offset_top = -196; band.offset_bottom = -166
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(band)
	var health_bg := ColorRect.new()
	health_bg.color = Color(0, 0, 0, 0.45); health_bg.size = Vector2(HEALTH_W, 6)
	health_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(health_bg)
	_health_fill = ColorRect.new(); _health_fill.size = Vector2(HEALTH_W, 6)
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(_health_fill)
	_ammo = Label.new(); _ammo.position = Vector2(0, 8)
	_ammo.add_theme_font_size_override("font_size", 16)
	_ammo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ammo.add_theme_constant_override("outline_size", 4)
	_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(_ammo)
	_band = band  # M23: hidden while hud_gta draws health + ammo itself
	_wheel = Control.new()
	_wheel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.visible = false
	_wheel.draw.connect(_wheel_draw)
	_ui.add_child(_wheel)

func _update_ui(delta: float) -> void:
	if _ui == null: return
	var ch := _character()
	var w := _weapon()
	var melee := _is_melee(w)
	var on_foot := main_ref != null and bool(main_ref.get("on_foot"))
	# D-034: behind the wheel with a drive-by weapon the reticle stays up — the
	# player used to fire blind. Melee slots and non-driveby guns still hide it.
	var driveby := main_ref != null and not on_foot and not melee \
		and not w.is_empty() and bool(w.get("driveby", false))
	var active := (on_foot and ch != null) or driveby
	if not active and _wheel_open:
		_wheel_close(false)
	_ui.visible = active
	if not active: return
	if _band != null:
		var sys: Variant = main_ref.get("systems")
		_band.visible = not (sys is Dictionary and (sys as Dictionary).has("hud_gta"))
	if _cross != null: _cross.visible = not melee
	# The ring IS the spread: radians -> pixels, so the crosshair never lies
	# about where the next round can land — and it reads the LIVE weapon's
	# numbers, so switching guns visibly changes the cone.
	var spread_now := _spread(ch) if ch != null else float(w.get("driveby_spread", 0.075))
	var target_r := clampf(spread_now * SPREAD_TO_PX, RING_MIN_PX, RING_MAX_PX)
	_ring_r = move_toward(_ring_r, target_r, RING_RATE * 2.5 * delta)
	# The crosshair goes hot red the moment the centre ray rests on a valid
	# target — the "you may fire" light.
	var hot := Color(1.0, 0.30, 0.24) if _on_target else Color(1, 1, 1, 0.9)
	if _dot != null: _dot.color = hot
	var tick_c := Color(1.0, 0.30, 0.24, 0.9) if _on_target else Color(1, 1, 1, 0.75)
	for t in _ticks:
		t.visible = true
		t.color = tick_c
	_ticks[0].position = Vector2(-1, -_ring_r - 8); _ticks[1].position = Vector2(-1, _ring_r)
	_ticks[2].position = Vector2(-_ring_r - 8, -1); _ticks[3].position = Vector2(_ring_r, -1)
	var hm := _hitmark_t > 0.0
	var hc := Color(1.0, 0.55, 0.2) if _hitmark_kill else Color(1, 1, 1, 0.95)
	for i in _marks.size():
		_marks[i].visible = hm
		if hm:
			_marks[i].color = hc
			var dx := 7.0 if i < 2 else -7.0
			var dy := 7.0 if i % 2 == 0 else -7.0
			_marks[i].position = Vector2(dx - 4.5, dy - 1)
	_ammo.text = _ammo_text(w, melee)
	var frac := 1.0  # poll character.health / max_health once the controller has it
	var h: Variant = ch.get("health") if ch != null else null
	if h is float or h is int:
		var mh: Variant = ch.get("max_health")
		var top := float(mh) if (mh is float or mh is int) and float(mh) > 0.0 else 100.0
		frac = clampf(float(h) / top, 0.0, 1.0)
	_health_fill.size.x = HEALTH_W * frac
	_health_fill.color = Color(0.85, 0.25, 0.2).lerp(Color(0.35, 0.8, 0.4), frac)


## "SNUB PISTOL  12 | oo" — name first so a switch reads instantly. Melee
## slots show the name alone; there is nothing to count.
func _ammo_text(w: Dictionary, melee: bool) -> String:
	var name_s := String(w.get("name", "—"))
	if melee: return name_s
	if _reload_t > 0.0: return "%s  RELOADING…" % name_s
	var res := _reserves[_slot]
	var res_s := "∞" if res < 0 else str(res)
	return "%s  %d | %s" % [name_s, _mags[_slot], res_s]

# ============================== PLUMBING =====================================
func _fetch(prop: String) -> Node3D:  # validated Node3D read off main_ref
	var v: Variant = main_ref.get(prop) if main_ref != null else null
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null

func _character() -> Node3D: return _fetch("character")

func _camera() -> Camera3D: return _fetch("camera") as Camera3D

func _add_heat(n: int) -> void:
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"): pol.call("add_heat", n)

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var node: Variant = (sys as Dictionary).get(peer_name)
		if node is Node and is_instance_valid(node): return node
	return null
