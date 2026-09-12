extends Node
## MELEE v1 (M16) — hands first. A repo man settles things before he reaches
## for iron. LMB throws a jab / cross / heavy hook on a 3-beat chain; RMB holds
## a guard. Reach is a SPHERE SHAPE CAST, never a ray — a fist is wide, and a
## thin line down the crosshair would whiff on anyone standing a shoulder's
## width off centre. Pedestrians take a stagger then go down; officers route
## through foot_cops' own public API (which prices their heat); cars and props
## take a modest shove.
##
## THE RAIL (canon, no-torture): the moment a target is DOWN it cannot be
## struck again. There are no ground attacks in this game and there never will
## be. A body in the "pedestrian" or "officer" group that is NOT frozen is a
## body in its knockdown tumble — melee skips it entirely: no impulse, no API
## call, no heat, no shake, no sound. The swing whiffs through the air.
##
## CONTRACT WITH combat.gd (Shooting agent's weapon inventory): melee only
## acts while the selected weapon is of type "melee" (slot 0 FISTS, or BAT).
## `combat.current_weapon_id` is polled null-safely — if the property does not
## exist yet, we assume FISTS, so this system is testable standing alone. When
## a gun is selected, LMB/RMB are combat's and melee is completely silent.
##
## We NEVER edit character_factory.gd: the swing is choreographed by posing the
## rig dict's public joint nodes (sh_0/sh_1/el_0/el_1/torso/head) in aim_pose's
## grammar — exp-decay lerps toward per-phase targets — from _process, which
## runs after player_character's _physics_process gait for the frame, so the
## strike is the last thing written before the draw. The lerp runs on OUR
## state and the result is written absolutely; see POSE_BLEND for why, and for
## which three axes melee has to put back itself.
##
## ENTIRELY INERT in smoke mode. No HUD (nothing to draw), so no Control nodes
## and no MOUSE_FILTER trap. Peers bound lazily through main.systems.

# ============================== TUNABLES =====================================
const RNG_SEED := 0xFA57; const MIX_RATE := 22050
const WEAPON_DIR := "res://data/weapons"

# --- Weapon defaults. data/weapons/*.json is the source of truth; these are
# the fallbacks so melee works in a tree where the data files never landed.
# `reach` is the distance from the character's centreline to the CENTRE of the
# strike sphere; effective reach is reach + STRIKE_RADIUS.
const DEFAULT_FISTS := {
	"id": "fists", "name": "FISTS", "type": "melee",
	"reach": 1.1, "damage": 12, "swing_interval": 0.45, "knockdown": false}
const DEFAULT_BAT := {
	"id": "bat", "name": "BAT", "type": "melee",
	"reach": 1.7, "damage": 30, "swing_interval": 0.65, "knockdown": true}

# --- The strike loop. Fractions are of the weapon's own swing_interval, so a
# slow bat and a fast jab share one set of proportions.
const STRIKE_RADIUS := 0.55       # m: the sphere cast — fists are WIDE
const STRIKE_HEIGHT := 1.15       # m above the feet-origin character: torso line
const WINDUP_FRAC := 0.30         # nothing connects before this
const STRIKE_END := 0.52          # ACTIVE FRAMES are [WINDUP_FRAC, STRIKE_END)
const ARC_DOT := 0.60             # cos(~53 deg): the swing's forward arc
const COMBO_LEN := 3              # jab, cross, heavy hook
const COMBO_WINDOW := 0.50        # s after a swing ends to keep the chain alive
const HEAVY_INDEX := 2            # the third beat is the heavy one
const HEAVY_DAMAGE := 1.6         # ...and it hits this much harder
const HEAVY_LUNGE := 2.6          # m/s of forward step on the ender
const CROUCH_REACH := 0.85        # crouched strikes are shorter (movement meta)
const MAX_RESULTS := 12           # shape query cap; one target resolved per swing

# --- Reactions.
const PED_HITS_TO_DOWN := 2       # solid fist hits; the heavy ender skips the queue
const PED_POP := 90.0             # up-fling added to the carry impulse (N*s)
const IMPULSE_PER_DAMAGE := 18.0  # fists 12 -> 216 N*s (combat's bullet is 220)
const OFFICER_HEAD := false       # a fist to the hat is not a headshot
const HITS_META := "melee_hits"   # our own per-ped stagger count

# --- Consequences. The once-per-ped charge meta is combat.gd's LITERAL string:
# whoever gets there first pays, and nobody double-charges.
const PED_CHARGE_META := "combat_ped_charged"
const PED_HEAT := 1; const PED_RESPECT := -2   # knocking a civilian down
const HEAT_RADIUS := 22.0         # a fistfight is quieter than a gunshot (45 m)
const HEAT_WINDOW := 8.0          # ...and draws at most 1 heat per 8 s

# --- Guard (RMB held). RESERVED: nothing reduces incoming damage yet. The hook
# is `guard_damage_mult()` — when foot_cops or police_gunfire want a block to
# matter they multiply their damage by it. Spec for whoever takes that up:
# officer melee at contact range should deal ~6 hp, halved on a guard, and
# never through a downed player.
const GUARD_DAMAGE_MULT := 0.5    # RESERVED — read by nobody yet, on purpose
# ALSO DELIBERATELY NOT DONE: capping the stride mid-swing. combat.gd hands the
# `combat_speed_cap` meta over while a melee weapon is selected (it removes it
# every tick), so the channel is free — `ch.set_meta("combat_speed_cap", 3.4)`
# while is_striking would stop sprint-punching. It is the Movement agent's
# stride to spend, not ours, and they own player_character.gd; left as a note.

# --- Choreography (radians). Same grammar as aim_pose — targets plus an
# exp-decay lerp — but the lerp runs on OUR OWN state, not on the joint's
# current rotation, and the result is written absolutely. That matters: the
# factory's gait writes the same joints every physics tick, so lerping from
# whatever it left behind converges to a BLEND of walk and punch (measured:
# the fist reached 63% of its target and the swing read as a lazy reach).
# Owning the value and writing it wins the frame outright.
#
# AXIS OWNERSHIP. animate() writes sh.x, el.x, torso.x/z and head.x — drop
# those and the gait takes them straight back, no cleanup needed. It never
# touches sh.z, torso.y or head.y, so whatever melee leaves there is permanent:
# those three are unwound to exactly zero on the way out (see _release).
const POSE_BLEND := 28.0          # snappy: settles in ~4 frames, entry still eases
const POSE_EPS := 0.002           # unwound-enough threshold on the free axes
const P_SH0X := 0; const P_SH1X := 1; const P_EL0X := 2; const P_EL1X := 3
const P_SH0Z := 4; const P_SH1Z := 5; const P_TORY := 6
const P_HEADX := 7; const P_HEADY := 8
const POSE_N := 9
# JOINT SIGN LAW (M16 fix): a limb hangs down -Y, so POSITIVE rotation.x
# swings it FORWARD (-Z). Elbow flexion is forward = POSITIVE; only the
# wind-up pulls the shoulder BACK (negative). These constants were authored
# against character_factory's inverted elbow/aim signs, so every punch landed
# BEHIND Book. Signs corrected here to match the fixed factory.
const SH_REST := -0.15; const SH_COCK := -0.55     # cock = arm drawn BACK
const SH_PUNCH := 1.55; const SH_PUNCH_HEAVY := 1.78   # punch = arm FORWARD
const EL_REST := 0.30; const EL_COCK := 1.80; const EL_PUNCH := 0.10
const OFF_SH := -0.35; const OFF_EL := 1.50    # the hand you're not throwing
const TWIST := 0.30; const TWIST_HEAVY := 0.42; const TWIST_BAT := 0.55
const HEAD_DIP := 0.12
const GUARD_SH := 0.55; const GUARD_EL := 2.05   # forearms UP in FRONT
const GUARD_SH_Z := 0.30; const GUARD_TWIST := -0.18

# --- Feel.
const TRAUMA_FIST := 0.10; const TRAUMA_BAT := 0.18  # camera kick on CONNECT
const TRAUMA_HEAVY := 1.5                            # ender multiplier

# --- Audio (22050 mono, built once at setup; pooled on the character).
const AUDIO_POOL := 3
const WHOOSH_DB := -17.0; const THOCK_DB := -8.0; const CRACK_DB := -7.0
const UNIT_SIZE := 11.0; const MAX_DIST := 90.0

# --- The bat prop. Parented to the rig's PUBLIC right-forearm node, so it
# rides every pose this file writes and every gait step the factory writes.
const BAT_LOCAL := Vector3(0.02, -0.33, 0.0)
# Pitch found by rendering a sweep, not by algebra: the forearm's local frame
# tumbles through the swing, and -1.35 (the "obvious" -77 deg) put the barrel
# down and BEHIND the fist at full extension.
# Re-derived after the joint-sign fix: BAT_PITCH 2.60 existed to compensate an
# arm that pointed BACKWARD. With the forearm now flexing forward, the barrel
# leads the hands at a natural slight upward rake.
const BAT_PITCH := -0.55          # rad: barrel leads the hands, raked up

# ============================== STATE ========================================
var is_guarding := false          # public: RMB held with a melee weapon up
var is_striking := false          # public: mid-swing (windup through recovery)
var main_ref: Node = null

var _rng := RandomNumberGenerator.new()
var _defs: Dictionary = {}        # weapon id -> def dict (all types, so we can
                                  # recognise a GUN and stand down)
var _swing_t := -1.0              # s into the current swing; <0 = idle
var _swing_len := 0.45            # this swing's interval (from the weapon)
var _swing_side := 1              # 0 = left (jab), 1 = right (cross / hook)
var _swing_heavy := false
var _swing_two_handed := false
var _swing_hit := false           # one connect per swing
var _combo := 0                   # next beat index
var _combo_t := 0.0               # s left to keep the chain alive
var _heat_window := 0.0
var _pose := PackedFloat32Array() # our own joint state (see POSE_BLEND)
var _posing := false              # _pose is seeded and live
var _releasing := false           # unwinding sh.z / torso.y / head.y to zero
var _bat: Node3D = null           # prop, child of rig["el_1"]
var _whoosh: AudioStreamWAV = null
var _thock: AudioStreamWAV = null
var _crack: AudioStreamWAV = null
var _players: Array[AudioStreamPlayer3D] = []
var _pool_i := 0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return  # smoke gate: inert
	_rng.seed = RNG_SEED
	_pose.resize(POSE_N)
	_load_weapons()
	_whoosh = _build_whoosh(); _thock = _build_thock(); _crack = _build_crack()


# ============================== WEAPON RESOLUTION ============================
## Every weapon in data/weapons is loaded, guns included — knowing a pistol is
## a "gun" is how we know to keep our hands in our pockets. A tree with no data
## directory still fights: FISTS and BAT fall back to the constants above.
func _load_weapons() -> void:
	var dir := DirAccess.open(WEAPON_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".json"):
				var def := _read_def(WEAPON_DIR + "/" + fname)
				if not def.is_empty(): _defs[def["id"]] = def
			fname = dir.get_next()
		dir.list_dir_end()
	if not _defs.has("fists"): _defs["fists"] = DEFAULT_FISTS.duplicate()
	if not _defs.has("bat"): _defs["bat"] = DEFAULT_BAT.duplicate()


func _read_def(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty(): return {}
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary): return {}
	var d := parsed as Dictionary
	var id: Variant = d.get("id")
	if not (id is String) or (id as String).is_empty(): return {}
	return d


## The weapon melee is holding RIGHT NOW, or {} when it isn't our turn.
## combat.current_weapon_id is polled with get() — a property the Shooting
## agent may not have landed yet returns null, and null means FISTS.
func active_weapon() -> Dictionary:
	var id := "fists"
	var c := _peer("combat")
	if c != null:
		var cur: Variant = c.get("current_weapon_id")
		if cur is String and not (cur as String).is_empty(): id = cur as String
		elif cur is StringName and not String(cur).is_empty(): id = String(cur)
	var def: Variant = _defs.get(id)
	if not (def is Dictionary):
		# An id we have no file for. Only "fists" is assumed — an unknown id is
		# far more likely to be a gun we've never heard of than a new fist.
		return DEFAULT_FISTS.duplicate() if id == "fists" else {}
	var dd := def as Dictionary
	return dd if String(dd.get("type", "")) == "melee" else {}


## Distance at which a target's ORIGIN stops being reachable: the sphere's
## centre sits at `reach`, and the sphere itself is STRIKE_RADIUS wide.
func effective_reach(def: Dictionary, crouched := false) -> float:
	var r := float(def.get("reach", DEFAULT_FISTS["reach"]))
	if crouched: r *= CROUCH_REACH
	return r + STRIKE_RADIUS


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	_heat_window = maxf(_heat_window - delta, 0.0)
	_combo_t = maxf(_combo_t - delta, 0.0)
	if _combo_t <= 0.0: _combo = 0            # chain lapsed: back to the jab
	var ch := _character()
	if main_ref == null or not bool(main_ref.get("on_foot")) or ch == null:
		_stand_down(); return                 # holstered in a car
	var hp: Variant = ch.get("health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		_stand_down(); return                 # the dead don't throw hands
	var def := active_weapon()
	if def.is_empty():
		_stand_down(); return                 # a gun is up: LMB/RMB are combat's
	_ensure_audio(ch); _ensure_prop(ch, def)
	is_guarding = Input.is_action_pressed("aim")
	if _swing_t >= 0.0:
		_swing_t += delta
		var t := _swing_t / _swing_len
		if not _swing_hit and t >= WINDUP_FRAC and t < STRIKE_END:
			_resolve_strike(ch, def)
		if _swing_t >= _swing_len:
			_swing_t = -1.0; is_striking = false
	elif Input.is_action_just_pressed("fire") and not is_guarding:
		_begin_swing(ch, def)


## The pose runs on the IDLE frame, after player_character's gait has written
## the rig for this physics tick — last writer before the draw call wins, which
## is how a strike overrides a walk without either file importing the other.
func _process(delta: float) -> void:
	var live := _swing_t >= 0.0 or is_guarding
	if not live and not _releasing:
		_posing = false; return
	var ch := _character()
	if ch == null: _posing = false; _releasing = false; return
	var r := _rig_of(ch)
	if r.is_empty(): return
	if not _posing:
		_seed_pose(r); _posing = true
	if live: _releasing = true                  # there will be axes to unwind
	var tgt := PackedFloat32Array(); tgt.resize(POSE_N)
	if _swing_t >= 0.0: _swing_targets(tgt)
	elif is_guarding: _guard_targets(tgt)
	# releasing: targets stay at zero, which is exactly where they belong
	var k := 1.0 - exp(-POSE_BLEND * delta)
	for i in POSE_N: _pose[i] = lerpf(_pose[i], tgt[i], k)
	_write_pose(r, live)
	if not live and absf(_pose[P_SH0Z]) < POSE_EPS and absf(_pose[P_SH1Z]) < POSE_EPS \
			and absf(_pose[P_TORY]) < POSE_EPS and absf(_pose[P_HEADY]) < POSE_EPS:
		_zero_free(r); _releasing = false; _posing = false


## Drop everything: driving, dead, or holding a gun. The gait re-takes the
## joints it owns on its own, but the three axes it never writes have to be put
## back by hand or Book walks around bladed with his head cocked forever.
func _stand_down() -> void:
	is_guarding = false; is_striking = false
	_swing_t = -1.0; _combo = 0; _combo_t = 0.0
	if _bat != null and is_instance_valid(_bat): _bat.visible = false
	if not _releasing and not _posing: return
	var ch := _character()
	if ch != null:
		var r := _rig_of(ch)
		if not r.is_empty(): _zero_free(r)
	_releasing = false; _posing = false


# ============================== THE STRIKE LOOP ==============================
## Beat 0 jab (left), beat 1 cross (right), beat 2 heavy hook (right) — the
## ender lands harder, lunges a step, and puts a pedestrian down on its own.
func _begin_swing(ch: Node3D, def: Dictionary) -> void:
	var idx := _combo % COMBO_LEN
	_swing_len = maxf(float(def.get("swing_interval", 0.45)), 0.05)
	_swing_side = 0 if idx == 0 else 1
	_swing_heavy = idx == HEAVY_INDEX
	_swing_two_handed = bool(def.get("two_handed",
		float(def.get("reach", 1.1)) >= 1.5))
	if _swing_two_handed: _swing_side = 1     # a bat is swung right-handed
	_swing_t = 0.0; _swing_hit = false; is_striking = true
	_combo = (idx + 1) % COMBO_LEN
	_combo_t = _swing_len + COMBO_WINDOW
	var heavy_swing := bool(def.get("knockdown", false))
	_play(_whoosh, WHOOSH_DB, 0.70 if heavy_swing else 1.0)
	if _swing_heavy and not _crouched(ch) and ch is CharacterBody3D:
		var body := ch as CharacterBody3D
		if body.is_on_floor():                # step INTO the hook
			var fwd := -ch.global_transform.basis.z; fwd.y = 0.0
			if fwd.length() > 0.01:
				body.velocity += fwd.normalized() * HEAVY_LUNGE


## SHAPE CAST, not a ray. A sphere of STRIKE_RADIUS is dropped at torso height
## `reach` metres down the character's facing; everything it touches is then
## gated on planar distance (<= reach + radius) and the forward arc. The sphere
## is the honest broadphase — the gate is what makes the number quotable.
func _resolve_strike(ch: Node3D, def: Dictionary) -> void:
	_swing_hit = true                          # one connect per swing, hit or miss
	var world := ch.get_world_3d()
	if world == null: return
	var space := world.direct_space_state
	if space == null: return
	var crouched := _crouched(ch)
	var reach := float(def.get("reach", 1.1)) * (CROUCH_REACH if crouched else 1.0)
	var limit := reach + STRIKE_RADIUS
	var fwd := -ch.global_transform.basis.z; fwd.y = 0.0
	if fwd.length() < 0.01: return
	fwd = fwd.normalized()
	var origin := ch.global_position + Vector3.UP * STRIKE_HEIGHT
	var shape := SphereShape3D.new(); shape.radius = STRIKE_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, origin + fwd * reach)
	q.collide_with_bodies = true; q.collide_with_areas = false
	if ch is CollisionObject3D: q.exclude = [(ch as CollisionObject3D).get_rid()]
	var best: RigidBody3D = null
	var best_d := INF
	for hit: Dictionary in space.intersect_shape(q, MAX_RESULTS):
		var body: Variant = hit.get("collider")
		if not (body is RigidBody3D) or not is_instance_valid(body): continue
		var rb := body as RigidBody3D
		if _is_down(rb): continue              # THE RAIL: never strike the downed
		var sep := rb.global_position - ch.global_position; sep.y = 0.0
		var d := sep.length()
		if d > limit or d < 0.01: continue      # honest reach
		if sep.normalized().dot(fwd) < ARC_DOT: continue  # honest arc
		if d < best_d: best_d = d; best = rb
	if best == null: return                     # a whiff: the whoosh was it
	_land(best, ch, def, fwd)


## A connect. Peds go to their own knockdown machine, officers to theirs, and
## everything else takes a shove — plus the shake and the thock that sell it.
func _land(rb: RigidBody3D, ch: Node3D, def: Dictionary, fwd: Vector3) -> void:
	var dmg := float(def.get("damage", 12)) * (HEAVY_DAMAGE if _swing_heavy else 1.0)
	var impulse := fwd * dmg * IMPULSE_PER_DAMAGE
	var heavy_weapon := bool(def.get("knockdown", false))
	var arm := rb.global_position - ch.global_position
	if rb.is_in_group("pedestrian"):
		_land_ped(rb, ch, impulse, heavy_weapon, arm)
	elif rb.is_in_group("officer"):
		var fc := _peer("foot_cops")
		if fc != null and fc.has_method("officer_shot"):
			fc.call("officer_shot", rb, OFFICER_HEAD)   # THEIR api prices the heat
		rb.apply_impulse(impulse + Vector3.UP * PED_POP * 0.5, arm)
	else:                                        # cars, props, debris
		if rb.freeze:
			var inter := _peer("interactables")     # a punched hydrant still geysers
			if inter != null and inter.has_method("prop_shot"):
				inter.call("prop_shot", rb)
			if rb.freeze: rb.freeze = false          # parked stock rocks on its springs
		rb.apply_impulse(impulse, arm)
	_play(_crack if heavy_weapon else _thock,
		CRACK_DB if heavy_weapon else THOCK_DB,
		_rng.randf_range(0.94, 1.07))
	var tr := TRAUMA_BAT if heavy_weapon else TRAUMA_FIST
	if _swing_heavy: tr *= TRAUMA_HEAVY
	var cam := _camera()
	if cam != null and cam.has_method("add_trauma"): cam.call("add_trauma", tr)
	_witness_heat(ch)


## Fists stagger first and drop second: one clean hit rocks a man, the follow-up
## or the hook puts him on the pavement. A bat needs one. The knockdown itself
## is pedestrians.gd's — we only ask, then add the carry impulse.
func _land_ped(ped: RigidBody3D, ch: Node3D, impulse: Vector3,
		heavy_weapon: bool, arm: Vector3) -> void:
	var hits := int(ped.get_meta(HITS_META, 0)) + 1
	ped.set_meta(HITS_META, hits)
	var down := heavy_weapon or _swing_heavy or hits >= PED_HITS_TO_DOWN
	if not down: return                          # STAGGER: he keeps his feet
	var peds := _peer("pedestrians")
	if peds != null and peds.has_method("force_knockdown"):
		peds.call("force_knockdown", ped, ch)     # WALK -> DOWN, unfreezes
	if ped.freeze: ped.freeze = false
	ped.apply_impulse(impulse + Vector3.UP * PED_POP, arm)
	ped.set_meta(HITS_META, 0)                   # a fresh count if he gets back up
	if ped.has_meta(PED_CHARGE_META): return     # combat's literal meta: pay once
	ped.set_meta(PED_CHARGE_META, true)
	_add_heat(PED_HEAT, "ASSAULTED A BYSTANDER")
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_respect"):
		repo.call("add_respect", PED_RESPECT, "")


## THE RAIL, in one line of state everyone already publishes: pedestrians and
## officers walk as FROZEN kinematic bodies and are unfrozen the instant they
## are knocked down (both systems do `body.freeze = false` inside their own
## knockdown). So an unfrozen one is a downed one, and downed is untouchable.
## It self-clears too — pedestrians.gd re-freezes a ped when it dusts itself
## off, and he is fair game again the moment he is back on his feet.
func _is_down(rb: RigidBody3D) -> bool:
	return not rb.freeze and (rb.is_in_group("pedestrian") or rb.is_in_group("officer"))


## Throwing hands where people can see you is a misdemeanour, at most once per
## window. Radius is half of gunfire's — a scuffle doesn't carry a block.
func _witness_heat(ch: Node3D) -> void:
	if _heat_window > 0.0: return
	for g: String in ["pedestrian", "police"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D and is_instance_valid(n) and (n as Node3D) \
					.global_position.distance_to(ch.global_position) <= HEAT_RADIUS:
				_heat_window = HEAT_WINDOW; _add_heat(1, "BRAWLING IN PUBLIC"); return


## RESERVED hook for incoming damage. Nothing calls it yet — foot_cops owns the
## decision about whether its officers throw punches at all, and this is the
## number they'd multiply by if a raised guard should matter.
func guard_damage_mult() -> float:
	return GUARD_DAMAGE_MULT if is_guarding else 1.0


# ============================== CHOREOGRAPHY =================================
## Windup cocks the arm and twists the torso away from the target; the active
## window drives the fist through and twists into it; recovery falls back to
## neutral, where the gait is waiting to take its joints back.
func _swing_targets(tgt: PackedFloat32Array) -> void:
	var t := clampf(_swing_t / _swing_len, 0.0, 1.0)
	var sgn := 1.0 if _swing_side == 1 else -1.0
	var punch := SH_PUNCH_HEAVY if _swing_heavy else SH_PUNCH
	var twist := TWIST_BAT if _swing_two_handed else \
		(TWIST_HEAVY if _swing_heavy else TWIST)
	var sh_x := 0.0; var el_x := 0.0; var tw := 0.0; var hd := 0.0
	if t < WINDUP_FRAC:
		var u := t / WINDUP_FRAC
		sh_x = lerpf(SH_REST, SH_COCK, u); el_x = lerpf(EL_REST, EL_COCK, u)
		tw = lerpf(0.0, -twist * sgn, u); hd = lerpf(0.0, -0.05, u)
	elif t < STRIKE_END:
		var u := (t - WINDUP_FRAC) / (STRIKE_END - WINDUP_FRAC)
		sh_x = lerpf(SH_COCK, punch, u); el_x = lerpf(EL_COCK, EL_PUNCH, u)
		tw = lerpf(-twist * sgn, twist * sgn, u); hd = lerpf(-0.05, HEAD_DIP, u)
	else:
		var u := (t - STRIKE_END) / (1.0 - STRIKE_END)
		sh_x = lerpf(punch, SH_REST, u); el_x = lerpf(EL_PUNCH, EL_REST, u)
		tw = lerpf(twist * sgn, 0.0, u); hd = lerpf(HEAD_DIP, 0.0, u)
	var o := 1 - _swing_side
	tgt[P_SH0X + _swing_side] = sh_x
	tgt[P_EL0X + _swing_side] = el_x
	tgt[P_SH0Z + _swing_side] = 0.0             # the throwing arm squares up
	if _swing_two_handed:                       # both hands stay on the handle
		tgt[P_SH0X + o] = sh_x * 0.85
		tgt[P_EL0X + o] = el_x * 0.80
	else:                                       # the other hand keeps guard
		tgt[P_SH0X + o] = OFF_SH
		tgt[P_EL0X + o] = OFF_EL
	tgt[P_SH0Z + o] = GUARD_SH_Z if o == 0 else -GUARD_SH_Z
	tgt[P_TORY] = tw
	tgt[P_HEADX] = hd
	tgt[P_HEADY] = tw * -0.4                    # eyes stay on the man


## Forearms up, chin tucked, shoulders bladed. Cosmetic today — see
## guard_damage_mult() for the reserved half of this stance.
func _guard_targets(tgt: PackedFloat32Array) -> void:
	tgt[P_SH0X] = GUARD_SH; tgt[P_SH1X] = GUARD_SH
	tgt[P_EL0X] = GUARD_EL; tgt[P_EL1X] = GUARD_EL
	tgt[P_SH0Z] = GUARD_SH_Z; tgt[P_SH1Z] = -GUARD_SH_Z
	tgt[P_TORY] = GUARD_TWIST
	tgt[P_HEADX] = 0.10
	tgt[P_HEADY] = 0.0


## No pop on entry: our state starts wherever the gait had the joints.
func _seed_pose(rig: Dictionary) -> void:
	_pose[P_SH0X] = (rig["sh_0"] as Node3D).rotation.x
	_pose[P_SH1X] = (rig["sh_1"] as Node3D).rotation.x
	_pose[P_EL0X] = (rig["el_0"] as Node3D).rotation.x
	_pose[P_EL1X] = (rig["el_1"] as Node3D).rotation.x
	_pose[P_SH0Z] = (rig["sh_0"] as Node3D).rotation.z
	_pose[P_SH1Z] = (rig["sh_1"] as Node3D).rotation.z
	_pose[P_TORY] = (rig["torso"] as Node3D).rotation.y
	_pose[P_HEADX] = (rig["head"] as Node3D).rotation.x
	_pose[P_HEADY] = (rig["head"] as Node3D).rotation.y


## `live` gates only the axes the factory also writes — while unwinding we
## touch nothing but the three it does not, so the walk is never disturbed.
func _write_pose(rig: Dictionary, live: bool) -> void:
	(rig["sh_0"] as Node3D).rotation.z = _pose[P_SH0Z]
	(rig["sh_1"] as Node3D).rotation.z = _pose[P_SH1Z]
	(rig["torso"] as Node3D).rotation.y = _pose[P_TORY]
	(rig["head"] as Node3D).rotation.y = _pose[P_HEADY]
	if not live: return
	(rig["sh_0"] as Node3D).rotation.x = _pose[P_SH0X]
	(rig["sh_1"] as Node3D).rotation.x = _pose[P_SH1X]
	(rig["el_0"] as Node3D).rotation.x = _pose[P_EL0X]
	(rig["el_1"] as Node3D).rotation.x = _pose[P_EL1X]
	(rig["head"] as Node3D).rotation.x = _pose[P_HEADX]


func _zero_free(rig: Dictionary) -> void:
	(rig["sh_0"] as Node3D).rotation.z = 0.0
	(rig["sh_1"] as Node3D).rotation.z = 0.0
	(rig["torso"] as Node3D).rotation.y = 0.0
	(rig["head"] as Node3D).rotation.y = 0.0
	_pose[P_SH0Z] = 0.0; _pose[P_SH1Z] = 0.0
	_pose[P_TORY] = 0.0; _pose[P_HEADY] = 0.0


## The factory's rig dict, validated. Character agent owns the factory; these
## joint nodes are its documented public posing surface and we only pose them.
func _rig_of(ch: Node3D) -> Dictionary:
	var rig: Variant = ch.get("_rig")
	if not (rig is Dictionary): return {}
	var r := rig as Dictionary
	if r.is_empty() or not is_instance_valid(r.get("vis")): return {}
	for key: String in ["sh_0", "sh_1", "el_0", "el_1", "torso", "head"]:
		if not r.has(key) or not is_instance_valid(r[key]): return {}
	return r


# ============================== THE PROP =====================================
## The bat hangs off rig["el_1"] — a PUBLIC node of the factory's rig dict,
## parented to, never edited. It inherits the forearm's every rotation, so the
## swing above animates it for free.
##
## The mesh is bat-shaped, so it is opt-IN by name: a weapon json declares
## `"prop": "bat"` (assumed for id "bat") and anything else carries nothing
## rather than swinging a tire iron that renders as ash and pine tar. A new
## melee weapon wants its own branch here, not a shrug.
func _ensure_prop(ch: Node3D, def: Dictionary) -> void:
	var id := String(def.get("id", ""))
	var want := String(def.get("prop", "bat" if id == "bat" else "")) == "bat"
	if not want:
		if _bat != null and is_instance_valid(_bat): _bat.visible = false
		return
	if _bat != null and is_instance_valid(_bat) and _bat.is_inside_tree():
		_bat.visible = true; return
	var rig := _rig_of(ch)
	if rig.is_empty(): return
	var hand: Variant = rig.get("el_1")
	if not (hand is Node3D) or not is_instance_valid(hand): return
	_bat = Node3D.new()
	_bat.name = "BatProp"
	_bat.position = BAT_LOCAL
	_bat.rotation = Vector3(BAT_PITCH, 0.0, 0.0)
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.15, 0.13, 0.12); tape.roughness = 0.9
	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color(0.72, 0.60, 0.40); ash.roughness = 0.55
	_bat.add_child(_cyl(0.024, 0.026, 0.30, Vector3(0, 0.15, 0), tape))
	_bat.add_child(_cyl(0.030, 0.040, 0.44, Vector3(0, 0.52, 0), ash))
	(hand as Node3D).add_child(_bat)


func _cyl(r_bot: float, r_top: float, h: float, pos: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r_bot; m.top_radius = r_top; m.height = h
	m.radial_segments = 10; m.rings = 1; m.material = mat
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.position = pos
	return mi


# ============================== AUDIO ========================================
## Pooled players ride the character (they die with it on enter-vehicle, so the
## parent is re-checked every tick). tree_exiting stop + _exit_tree stop: the
## 4.7.1 audio-at-quit law.
func _ensure_audio(ch: Node3D) -> void:
	if not _players.is_empty() and is_instance_valid(_players[0]) \
			and _players[0].get_parent() == ch: return
	_players.clear()
	for i in AUDIO_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = UNIT_SIZE; p.max_distance = MAX_DIST
		p.tree_exiting.connect(p.stop); ch.add_child(p); _players.append(p)


func _play(stream: AudioStreamWAV, db: float, pitch: float) -> void:
	if stream == null or _players.is_empty(): return
	var p := _players[_pool_i]
	_pool_i = (_pool_i + 1) % _players.size()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree(): return
	p.stream = stream; p.volume_db = db; p.pitch_scale = pitch; p.play()


func _exit_tree() -> void:
	for p in _players:
		if p != null and is_instance_valid(p): p.stop()


## Air moving: noise through a one-pole low-pass that OPENS as the arm speeds
## up, under a swell-then-cut envelope. ~0.22 s.
func _build_whoosh() -> AudioStreamWAV:
	var n := 4850
	var s := PackedFloat32Array(); s.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		var env := sin(PI * pow(u, 0.75))            # swell in, cut off sharp
		var a := lerpf(0.06, 0.42, u)                # filter opens as it swings
		lp += (_rng.randf_range(-1.0, 1.0) - lp) * a
		s[i] = lp * env * 0.55 * minf(float(i) / 24.0, 1.0)
	return _wav(s)


## Knuckle on ribs: a short click transient over a fast 120->70 Hz thud. ~0.14 s.
func _build_thock() -> AudioStreamWAV:
	var n := 3100
	var s := PackedFloat32Array(); s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var click := _rng.randf_range(-1.0, 1.0) * exp(-190.0 * t) * 0.45
		phase += TAU * lerpf(120.0, 70.0, clampf(t / 0.14, 0.0, 1.0)) / float(MIX_RATE)
		var thud := sin(phase) * exp(-26.0 * t) * 0.8
		s[i] = (click + thud) * minf(float(i) / 8.0, 1.0)
	return _wav(s)


## Ash on bone: brighter, harder, a woody ring on top of the thud. ~0.18 s.
func _build_crack() -> AudioStreamWAV:
	var n := 3900
	var s := PackedFloat32Array(); s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var snap := _rng.randf_range(-1.0, 1.0) * exp(-120.0 * t) * 0.7
		var ring := sin(TAU * 640.0 * t) * exp(-42.0 * t) * 0.3
		phase += TAU * lerpf(150.0, 82.0, clampf(t / 0.18, 0.0, 1.0)) / float(MIX_RATE)
		var thud := sin(phase) * exp(-20.0 * t) * 0.75
		s[i] = (snap + ring + thud) * minf(float(i) / 8.0, 1.0)
	return _wav(s)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray(); bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE; w.stereo = false; w.data = bytes
	return w


# ============================== PLUMBING =====================================
## Movement owns player_character.gd — its state is read through metas ONLY.
func _crouched(ch: Node3D) -> bool:
	return ch.has_meta("is_crouched") and bool(ch.get_meta("is_crouched"))


func _fetch(prop: String) -> Node3D:
	var v: Variant = main_ref.get(prop) if main_ref != null else null
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


func _character() -> Node3D: return _fetch("character")


func _camera() -> Camera3D: return _fetch("camera") as Camera3D


func _add_heat(n: int, reason: String = "") -> void:
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"): pol.call("add_heat", n, reason)


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var node: Variant = (sys as Dictionary).get(peer_name)
		if node is Node and is_instance_valid(node): return node
	return null
