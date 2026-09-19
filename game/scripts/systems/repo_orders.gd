extends Node
## REPO ORDERS — THE HOOK, ENDLESS. The repeatable job that puts PEOPLE in the
## game's core verb. repo_board.gd gives the player nine derelict junkers in
## empty lots; this gives them a name, an address and a face. When the world is
## quiet — Book driving the wrecker, nothing on the hook, no scripted job — the
## LONGHORN app pushes a recovery order: a debtor, a car on a curb 120-450 m
## out, an amount outstanding, days past due, and a quota counter that never
## stops counting. Drive out and the person whose car it is walks out of their
## house. They plead, or they offer you two hundred dollars, or they call it in,
## or they square up. Hook it and get paid; press G and walk away and the app
## marks your rating.
##
## THE PAPER (story canon: "the paperwork is the joke, never the debtor"). One
## order in five is BAD PAPER — a lien held by a shell with Longhorn's own name
## on it, a note originated yesterday, a VIN still "PENDING", an account at a
## bank that closed in 2019, an owner who died in March. Every bad order carries
## its TELL in the push, and the debtor confirms it to your face if you get
## close enough to listen. Take a bad car anyway: respect -3 and `paper_taken`
## remembers. Walk away from one: respect +3 and `paper_burned` remembers. The
## system never tells the player which number is the good one.
##
## Data: data/mechanics/repo_orders.json (every tunable, every name, every line).
## Peers are ALL optional and null-checked — this boots headless with no HUD,
## no police, no pedestrians and no tow hook, and simply never pushes.

const DATA_PATH := "res://data/mechanics/repo_orders.json"
const REPO := preload("res://scripts/systems/repo_board.gd")     # PAD_CENTER / PAD_HALF
const PEDS := preload("res://scripts/systems/pedestrians.gd")    # PED_HALF only
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const BEACON := preload("res://scripts/world/beacon_kit.gd")
const RNG_SEED := 0xB00C13

# ============================== PUBLIC CONTRACT ==============================
enum State { IDLE, PUSHED, HOOKED }
enum Reaction { PLEAD, CALL_IT_IN, OFFER, FIGHT }

signal order_pushed(bad: bool)
signal order_closed(outcome: String)   # "delivered" | "voided" | "expired"

const BASE_PAY := {"sedan": 300, "pickup": 450}
const RANK_NAMES: Array[String] = ["ROOKIE", "HAND", "DRIVER", "CLOSER", "PARTNER"]
const RANK_AT: Array[int] = [0, 4, 10, 18, 30]
const RANK_MULT: Array[float] = [1.0, 1.15, 1.3, 1.45, 1.6]

var state: int = State.IDLE
var active := false
var rank: int = 1
var deliveries: int = 0
var paper_taken: int = 0
var paper_burned: int = 0
var quota_done: int = 0
var quota_day: int = 0
var cfg: Dictionary = {}

# ============================== BODY SHAPES ==================================
# Straight off parked_cars.gd so an order car is indistinguishable from the
# curb stock it is parked among — that is the whole point of the beacon.
const SIZE := {"sedan": Vector3(1.9, 1.05, 4.4), "pickup": Vector3(2.15, 1.3, 5.2)}
const RIDE := {"sedan": 0.85, "pickup": 1.1}
const WHEEL := {"sedan": 0.32, "pickup": 0.44}
const MASS := {"sedan": 1300.0, "pickup": 1750.0}
const CAR_FRICTION := 0.3            # parked_cars' tow-friendly sliding friction
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)   # the smoke lane stays sacred
const OCCUPIED_M := 7.0              # a slot with a towable this close is taken
const SIDEWALK_Y := 0.2              # lot/kerb slab top: where the debtor stands
const PAD_MAX_Y := 4.0               # repo_board's release test
const APP := "LONGHORN · RECOVERY"   # mission_kit's dispatcher voice (D-063)
# LONGHORN orange, one notch hotter than repo_board's target glow, and SHORTER
# than its 21 m column: the board's one contract still owns the tallest beacon
# downtown, and an order reads as the smaller, endless job next to it.
const ORANGE := Color(0.98, 0.45, 0.08)
const BEAM_HEIGHT := 16.0
const BEAM_WIDTH := 2.2
const BEAM_ALPHA := 0.28
const BEAM_ENERGY := 1.2
const BEAM_RING := 4.0
const SWEEP_EVERY := 1.5             # abandoned-car despawn check cadence (s)
# mission_kit owns ONE card panel, so a promoting delivery shows RECOVERED
# first and PROMOTED after it clears (kit's default card time is 6 s).
const PROMO_DELAY := 6.6

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _gap_t := 0.0
var _expire_t := 0.0
var _expire_armed := true
var _slots: Array[Vector3] = []
var _car: RigidBody3D = null
var _debtor: RigidBody3D = null
var _beacon: Node3D = null
var _tow: Node = null
var _prev_hooked: Node = null
var _abandoned: Array[RigidBody3D] = []
var _sweep_t := 0.0
var _models: Dictionary = {}
var _next_id := 0
var _tod_prev := -1.0
var _missed := false

# --- the live order ---------------------------------------------------------
var _id := 0
var _who := ""
var _cls := "sedan"
var _model := ""
var _year := 0
var _bad := false
var _reaction: int = Reaction.PLEAD
var _tell := ""
var _haul_m := 0.0
var _heat_drawn := false
var _heat_base := 0
var _promo_t := 0.0
var _spawn_pos := Vector3.ZERO
var _side := 1.0

# --- the debtor's script ----------------------------------------------------
var _met := false
var _line_t := 0.0
var _line_ix := 0
var _line_said := ""
var _call_t := 0.0
var _called := false
var _fight_t := 0.0
var _offer_open := false


# ============================== SETUP ========================================
func setup(main: Node) -> void:
	main_ref = main
	_rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		_disabled = true
		set_physics_process(false)
		return          # smoke gate: the loop spawns NOTHING and the line stays byte-stable
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	_load_models()
	_next_id = int(_n("order_id_base", 4471.0))
	_gap_t = _n("first_gap", 12.0)


## Naming bible §7a: a vehicle's canon name lives in the `name` field of its
## profile and NOWHERE else. The data file stores profile PATHS; the model name
## is read out of the profile here, so the fleet can be renamed in one place.
func _load_models() -> void:
	_models = {"sedan": "SEDAN", "pickup": "PICKUP"}
	var profiles: Variant = cfg.get("profiles", {})
	if not (profiles is Dictionary):
		return
	for key: Variant in (profiles as Dictionary):
		var f := FileAccess.open(str((profiles as Dictionary)[key]), FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).has("name"):
			_models[str(key)] = str((parsed as Dictionary)["name"]).to_upper()


func _n(key: String, def: float) -> float:
	var v: Variant = cfg.get(key, def)
	return float(v) if (v is float or v is int) else def


func _txt(key: String, def: String) -> String:
	var v: Variant = cfg.get(key, def)
	return str(v) if v is String else def


func _list(key: String) -> Array:
	var v: Variant = cfg.get(key, [])
	return v if v is Array else []


func _pick(key: String, def: String) -> String:
	var a := _list(key)
	if a.is_empty():
		return def
	return str(a[_rng.randi_range(0, a.size() - 1)])


# ============================== PUBLIC API ===================================
## Force an order onto the board right now (probe/debug). Ignores the quiet
## rule and the gap; still needs an open curb slot somewhere in the city.
func push_now(bad_paper := false) -> bool:
	if _disabled or state != State.IDLE:
		return false
	return _push(bad_paper, true)


## LEAVE THE PAPER. Voids the order: respect by whether the paper was bad, one
## step of rank progress gone, and the app files it as a vehicle not located.
func walk_away() -> bool:
	if state != State.PUSHED:
		return false
	if _bad:
		paper_burned += 1
		_pay_respect(int(_n("respect_walk_bad", 3.0)), "LEFT THE PAPER")
	else:
		_pay_respect(int(_n("respect_walk_clean", 1.0)), "GAVE THEM THE WEEK")
	_say(APP, _txt("app_void", "ORDER {id} VOIDED.").format({"id": _id}))
	_demote_one()
	_close("voided")
	return true


## TAKE THE CASH. Live only while the debtor has an offer standing. Pays less
## than any delivery on purpose: this is a choice, never an optimisation.
func accept_offer() -> bool:
	if state != State.PUSHED or not _offer_open:
		return false
	_pay_money(int(_n("offer_amount", 200.0)), "CASH, NO QUESTIONS")
	_pay_respect(int(_n("respect_offer", 2.0)), _who)
	if _bad:
		paper_burned += 1
	_say(APP, _txt("app_offer_void", "ORDER {id} VOIDED.").format({"id": _id}))
	if _n("offer_demotes", 0.0) > 0.5:
		_demote_one()
	_close("voided")
	return true


func target() -> Node3D:
	return _car if is_instance_valid(_car) and _car.is_inside_tree() else null


func debtor() -> Node3D:
	return _debtor if is_instance_valid(_debtor) and _debtor.is_inside_tree() else null


func order_id() -> int:
	return _id


## The HUD's one line for this system. Distance is live, so it counts down.
func objective_text() -> String:
	var t := target()
	if t == null:
		return ""
	if state == State.HOOKED:
		var pad := Vector2(t.global_position.x - REPO.PAD_CENTER.x,
			t.global_position.z - REPO.PAD_CENTER.z).length()
		return "HAUL TO IMPOUND · %d m" % int(round(pad))
	var a := _actor()
	if state == State.PUSHED and a != null:
		var away := a.global_position.distance_to(t.global_position)
		return "ORDER %d · %s · %d %s · %d m" % [_id, _who, _year, _short_model(),
			int(round(away))]
	return ""


## The G prompt, for whoever draws prompts. "" when there is nothing to press.
func prompt_text() -> String:
	if state != State.PUSHED or not _in_choice_range():
		return ""
	if _offer_open:
		return "G — TAKE THE $%d" % int(_n("offer_amount", 200.0))
	return "G — WALK AWAY"


func rank_name() -> String:
	return RANK_NAMES[clampi(rank - 1, 0, RANK_NAMES.size() - 1)]


func rank_mult() -> float:
	return RANK_MULT[clampi(rank - 1, 0, RANK_MULT.size() - 1)]


## Delivery count the next rank starts at; 0 once there is no next rank.
func next_rank_at() -> int:
	return RANK_AT[rank] if rank < RANK_AT.size() else 0


func _short_model() -> String:
	var parts := _model.split(" ", false)
	return str(parts[parts.size() - 1]) if parts.size() > 0 else _model


# ============================== THE CLOCK ====================================
func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	_try_bind_tow()
	_tick_day()
	_tick_background(delta)
	if state == State.IDLE:
		_tick_idle(delta)
		return
	_tick_live(delta)


## The gap only runs while the road is quiet, so the app never pushes into a
## chase, a scripted job, or a haul already on the hook. 12 s of quiet on a
## fresh session; 40 + 0..20 s after every order closes.
func _tick_idle(delta: float) -> void:
	if not _quiet_world():
		return
	_gap_t -= delta
	if _gap_t > 0.0:
		return
	if not _push(_rng.randf() < _n("bad_paper_chance", 0.2), false):
		_gap_t = _n("retry_gap", 6.0)   # no open curb anywhere: try again shortly


## random_events._quiet_world(), with ONE difference: an order may push at heat
## 1. A constable behind you is the texture of the job, not an emergency; heat 2
## and up is a chase, and the app does not push into a chase.
func _quiet_world() -> bool:
	if main_ref.get("on_foot") == true:
		return false
	var pv := _player_vehicle()
	if pv == null or not pv.has_method("has_boom") or not bool(pv.call("has_boom")):
		return false
	var pol := _peer("police")
	if pol != null:
		var hv: Variant = pol.get("heat")
		if hv is int and int(hv) > 1:
			return false
	for key: String in ["mission_hook_and_ladder", "mission_second_collection",
			"mission_comin_down"]:
		var m := _peer(key)
		if m != null and int(m.get("state")) != 0:
			return false
	var repo := _peer("repo_board")
	if repo != null and repo.get("_delivering") == true:
		return false
	if _tow != null and is_instance_valid(_tow) and _tow.get("hooked_body") != null:
		return false
	return true


## An in-game day rolled over (sky_weather wraps time_of_day past 0). Reset the
## quota; if it went unmet, the next push opens with the region's favourite
## sentence. Missing quota costs nothing else in v1 — the dread is the feature.
func _tick_day() -> void:
	var sky := _peer("sky_weather")
	if sky == null:
		return
	var tv: Variant = sky.get("time_of_day")
	if not (tv is float or tv is int):
		return
	var tod := float(tv)
	if _tod_prev >= 0.0 and tod < _tod_prev - 1.0:
		quota_day += 1
		_missed = quota_done < int(_n("quota", 3.0))
		quota_done = 0
	_tod_prev = tod


# ============================== THE PUSH =====================================
## Build an order and put it on the curb. `forced` (the probe) drops the
## distance band so a push always finds a slot somewhere in the city.
func _push(bad_paper: bool, forced: bool) -> bool:
	var a := _actor()
	if a == null:
		return false
	var dmin := 0.0 if forced else _n("min_m", 120.0)
	var dmax := 1.0e9 if forced else _n("max_m", 450.0)
	var slot := _pick_slot(a.global_position, dmin, dmax)
	if not slot.is_finite():
		if forced:
			print("REPO ORDERS: push refused — no open curb slot (%d known) from %s" % [_slots.size(), a.global_position])
		return false
	_id = _next_id
	_next_id += _rng.randi_range(int(_n("order_id_step_min", 3.0)),
		int(_n("order_id_step_max", 41.0)))
	_who = "%s %s" % [_pick("first_names", "DARLENE"), _pick("last_names", "PRUITT")]
	_cls = "pickup" if _rng.randf() < _n("pickup_chance", 0.45) else "sedan"
	_model = str(_models.get(_cls, _cls.to_upper()))
	_year = _rng.randi_range(int(_n("year_min", 2009.0)), int(_n("year_max", 2022.0)))
	_bad = bad_paper
	_reaction = Reaction.CALL_IT_IN if _bad else _roll_reaction()
	var days := _rng.randi_range(int(_n("days_min", 31.0)), int(_n("days_max", 210.0)))
	var true_days := _rng.randi_range(int(_n("bad_days_min", 3.0)),
		int(_n("bad_days_max", 9.0)))
	var amount := _rng.randi_range(int(_n("amount_min", 2400.0)),
		int(_n("amount_max", 24000.0))) / 10 * 10
	var fields := {"id": _id, "name": _who, "year": _year, "model": _model,
		"days": days, "true_days": true_days, "amount": _commas(amount),
		"q": quota_done + 1, "quota": int(_n("quota", 3.0))}
	_tell = _pick("paper_tells", "VIN: PENDING").format(fields) if _bad else ""
	fields["tell"] = _tell
	_spawn_car(slot)
	_raise_beacon(Vector3(_spawn_pos.x, 0.05, _spawn_pos.z))
	_haul_m = _basis_distance(a, slot)
	_expire_t = _n("expire_seconds", 240.0)
	_expire_armed = true
	_heat_drawn = false
	_heat_base = _heat_now()
	_met = false
	_called = false
	_call_t = 0.0
	_line_t = 0.0
	_line_ix = 0
	_fight_t = 0.0
	_offer_open = false
	state = State.PUSHED
	active = true
	_say(APP, _txt("app_push", "ORDER {id} · {name}. Recover to impound.").format(fields),
		_n("line_seconds", 5.0) + 1.5)
	if _bad and _tell != "":
		_say(APP, _txt("app_tell", "ORDER {id} FLAG · {tell}.").format(fields))
	if _missed:
		_missed = false
		_say(APP, _txt("app_missed_quota", "Yesterday's numbers are visible to the region."))
	order_pushed.emit(_bad)
	return true


## What the distance bonus is measured on. "haul" (default) is the honest one:
## the drag from the curb to the impound pad — the work you are actually paid
## for. "fetch" pays for the drive out instead. One word in the data file.
func _basis_distance(a: Node3D, slot: Vector3) -> float:
	var pad := Vector2(REPO.PAD_CENTER.x, REPO.PAD_CENTER.z)
	var here := Vector2(slot.x, slot.z)
	if _txt("distance_basis", "haul") == "fetch":
		return Vector2(a.global_position.x, a.global_position.z).distance_to(here)
	return here.distance_to(pad)


func _roll_reaction() -> int:
	var w: Variant = cfg.get("reactions", {})
	var keys: Array[String] = ["plead", "call_it_in", "offer", "fight"]
	var vals: Array[float] = [0.42, 0.18, 0.22, 0.18]
	if w is Dictionary:
		for i in keys.size():
			var v: Variant = (w as Dictionary).get(keys[i], vals[i])
			if v is float or v is int:
				vals[i] = maxf(float(v), 0.0)
	var total := 0.0
	for v in vals:
		total += v
	if total <= 0.0:
		return Reaction.PLEAD
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in vals.size():
		acc += vals[i]
		if roll <= acc:
			return i
	return Reaction.PLEAD


## $18,240 reads like a statement; $18240 reads like a debug print.
func _commas(n: int) -> String:
	var digits := str(maxi(n, 0))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


# ============================== THE CURB =====================================
## An open curb slot in the distance ring, biased to mid-ring with some chance
## in it. parked_cars owns the slot grid; a slot with any towable within 7 m is
## already taken, and the smoke corridor is never used.
func _pick_slot(from: Vector3, dmin: float, dmax: float) -> Vector3:
	if _slots.is_empty():
		var parked := _peer("parked_cars")
		if parked != null and parked.has_method("_build_slots"):
			var got: Variant = parked.call("_build_slots")
			if got is Array:
				for v: Variant in got:
					if v is Vector3:
						_slots.append(v)
	var best := Vector3.INF
	var best_score := INF
	var towables := get_tree().get_nodes_in_group("towable")
	var mid := (dmin + minf(dmax, 450.0)) * 0.5
	for s in _slots:
		var d := Vector2(s.x - from.x, s.z - from.z).length()
		if d < dmin or d > dmax or CORRIDOR.has_point(Vector2(s.x, s.z)):
			continue
		var taken := false
		for t: Node in towables:
			if not (t is Node3D) or not is_instance_valid(t):
				continue
			var tp := (t as Node3D).global_position
			if Vector2(tp.x - s.x, tp.z - s.z).length() < OCCUPIED_M:
				taken = true
				break
		if taken:
			continue
		var score := absf(d - mid) + _rng.randf() * 30.0
		if score < best_score:
			best_score = score
			best = s
	return best


## The order car: a parked shell, frozen kinematic like the curb stock around
## it (parked_cars' law — a frozen car cannot be towed, so the hook unfreezes
## it). NOT in "civilian", so carjack will not let the player simply drive it
## away: the only way to close an order is the boom.
func _spawn_car(slot: Vector3) -> void:
	var size: Vector3 = SIZE.get(_cls, Vector3(1.9, 1.05, 4.4))
	var ride := float(RIDE.get(_cls, 0.85))
	_spawn_pos = Vector3(slot.x, ride, slot.z)
	_side = signf(slot.y) if absf(slot.y) > 0.5 else 1.0
	var body := RigidBody3D.new()
	body.name = "RepoOrder%d" % _id
	body.mass = float(MASS.get(_cls, 1300.0))
	var pm := PhysicsMaterial.new()
	pm.friction = CAR_FRICTION
	body.physics_material_override = pm
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.contact_monitor = true
	body.max_contacts_reported = 8
	body.add_to_group("towable")
	body.add_to_group("mission_target")   # hud_gta draws the gold ring for this group
	body.add_to_group("repo_order")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var vis := Node3D.new()
	body.add_child(vis)
	BODY_BUILDER.build(vis, _cls, size, _paint())
	_add_wheels(body, size, float(WHEEL.get(_cls, 0.32)), ride)
	body.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.0, -_side), Vector3.UP),
		_spawn_pos)
	add_child(body)   # Node3D under a plain Node: transform acts as global
	_car = body


func _add_wheels(body: RigidBody3D, size: Vector3, radius: float, ride: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.24
	mesh.radial_segments = 18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.roughness = 0.9
	var zoff := size.z * 0.5 - radius - 0.7
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new()
		w.mesh = mesh
		w.material_override = mat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = Vector3(c.x * (size.x * 0.5 - 0.075), radius - ride, c.y * zoff)
		body.add_child(w)


func _paint() -> Color:
	var pool := _list("paint")
	if not pool.is_empty():
		var c: Variant = pool[_rng.randi_range(0, pool.size() - 1)]
		if c is Array and (c as Array).size() >= 3:
			return Color(float((c as Array)[0]), float((c as Array)[1]),
				float((c as Array)[2]))
	return Color(0.72, 0.70, 0.66)


## LONGHORN orange, 16 m: taller than a stranded motorist's 14 m, shorter than
## the repo board's 21 m contract column. The ladder is the message. `at` is the
## GROUND point the beacon marks, never the body centre (D-015: a beacon pinned
## to y=0 buries its corona under any slab the car is standing on).
func _raise_beacon(at: Vector3) -> void:
	if _beacon != null and is_instance_valid(_beacon):
		return
	_beacon = BEACON.beacon(ORANGE, BEAM_HEIGHT, BEAM_WIDTH, BEAM_ALPHA, BEAM_ENERGY,
		BEAM_RING)
	_beacon.position = at
	add_child(_beacon)


## Where the car is standing right now: its centre minus half its collider.
func _ground_under_car() -> Vector3:
	if not is_instance_valid(_car):
		return Vector3(_spawn_pos.x, 0.05, _spawn_pos.z)
	var size: Vector3 = SIZE.get(_cls, Vector3(1.9, 1.05, 4.4))
	var p := _car.global_position
	return Vector3(p.x, clampf(p.y - size.y * 0.5, 0.0, 3.0), p.z)


# ============================== WHILE LIVE ===================================
func _tick_live(delta: float) -> void:
	if not is_instance_valid(_car) or not _car.is_inside_tree():
		_car = null           # somebody destroyed it, or the scene freed it
		_say(APP, _txt("app_expire", "ORDER {id} EXPIRED.").format({"id": _id}))
		_close("expired")
		return
	_watch_heat()
	_evaluate_hook_state()
	if state == State.IDLE:
		return                # a release on the pad already closed the order
	if state == State.PUSHED and _expire_armed:
		_expire_t -= delta
		if _expire_t <= 0.0:
			_expire()
			return
	_tick_debtor(delta)
	if state == State.PUSHED:
		_tick_choice()


## The medal asks "did this order cost you heat", not "are you wanted" — an
## order may push at heat 1, and that constable is not this job's fault.
func _watch_heat() -> void:
	if not _heat_drawn and _heat_now() > _heat_base:
		_heat_drawn = true


func _heat_now() -> int:
	var pol := _peer("police")
	if pol == null:
		return 0
	var hv: Variant = pol.get("heat")
	return int(hv) if hv is int else 0


# ============================== THE DEBTOR ===================================
func _tick_debtor(delta: float) -> void:
	var a := _actor()
	if a == null:
		return
	if not _met:
		if a.global_position.distance_to(_car.global_position) <= _n("debtor_range", 25.0):
			_meet(a)
		return
	if _line_t > 0.0:
		_line_t -= delta
		if _line_t <= 0.0:
			_second_line()
	if _fight_t > 0.0:
		_fight_t -= delta
		if _fight_t <= 0.0:
			_square_up()
	if _reaction == Reaction.CALL_IT_IN and not _called:
		_tick_call(delta, a)


## They come out of the house. A FOLLOWER, not a walker: they close on you and
## keep talking while you decide, and pedestrians.gd frees them on its own once
## you are 40 m gone. They are a person, not an obstacle — nothing in this
## system ever asks the player to hurt them.
func _meet(a: Node3D) -> void:
	_met = true
	var peds := _peer("pedestrians")
	var pos := Vector3(_spawn_pos.x + _side * _n("debtor_out_m", 3.0),
		SIDEWALK_Y + PEDS.PED_HALF, _spawn_pos.z)
	if peds != null and peds.has_method("spawn_follower_at"):
		var got: Variant = peds.call("spawn_follower_at", pos, Vector3(-_side, 0.0, 0.0),
			a, _n("follower_seconds", 120.0))
		if got is RigidBody3D:
			_debtor = got
	_line_ix = 0
	_first_line()


## BAD PAPER SPEAKS FIRST. The tell in the push is the app's slip; this is the
## person confirming it out loud, which is the only way the player can ever
## know for sure. Clean paper gets the reaction's own register.
func _first_line() -> void:
	var line := ""
	if _bad:
		line = _pick("bad_paper_lines", "I'm four days late, not four months.")
	elif _reaction == Reaction.OFFER:
		line = _pick("offer_lines", "Two hundred cash and you never saw this truck.")
		_offer_open = true
	elif _reaction == Reaction.FIGHT:
		line = _pick("fight_lines", "No. Not this one. Not today.")
		_fight_t = _n("fight_delay_s", 2.5)
	else:
		line = _pick("plead_lines", "I've got it Friday. I told the app Friday.")
		if _reaction == Reaction.PLEAD:
			_line_t = _n("plead_gap_s", 5.0)   # a second line lands five seconds later
	_line_said = line
	_line_ix = 1
	_say(_who, line, _n("line_seconds", 5.0))


func _second_line() -> void:
	if _bad or _reaction != Reaction.PLEAD or _line_ix > 1:
		return
	_line_ix = 2
	_say(_who, _pick_not("plead_lines", "Take it. I'm tired.", _line_said),
		_n("line_seconds", 5.0))


func _pick_not(key: String, def: String, avoid: String) -> String:
	var out := _pick(key, def)
	for _attempt in 3:
		if out != avoid:
			break
		out = _pick(key, def)
	return out


## CALL IT IN. They stand there with a phone while you work. Twelve seconds of
## you actually taking it — on the hook, or standing right on top of it — and
## the county knows. One star, once per order, and the reason says who told.
func _tick_call(delta: float, a: Node3D) -> void:
	if state != State.HOOKED:
		var d := debtor()
		var dp := d.global_position if d != null else _spawn_pos
		var cp := _car.global_position
		if Vector2(dp.x - cp.x, dp.z - cp.z).length() > _n("call_range_m", 20.0):
			return
		if a.global_position.distance_to(cp) > _n("call_hook_near_m", 10.0):
			return
	_call_t += delta
	if _call_t < _n("call_delay_s", 12.0):
		return
	_called = true
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", 1, "THE OWNER CALLED IT IN")


## They square up. The follower becomes one of melee.gd's brawlers and the
## order stays open — you can still hook it, and you can still walk away. The
## game never requires the player to swing back.
func _square_up() -> void:
	var d := debtor()
	if d == null:
		return
	var pos := d.global_position
	var facing := Vector3(-_side, 0.0, 0.0)
	var a := _actor()
	if a != null:
		var away := a.global_position - pos
		away.y = 0.0
		if away.length() > 0.1:
			facing = away.normalized()
	d.queue_free()
	_debtor = null
	var peds := _peer("pedestrians")
	if peds != null and peds.has_method("spawn_brawler_at"):
		var got: Variant = peds.call("spawn_brawler_at", pos, facing)
		if got is RigidBody3D:
			_debtor = got


## G, within 4 m of the person, with the car still on the curb. On an offer the
## same key takes the cash instead. One key, two meanings, because it is one
## decision: this order ends here, without the car.
func _tick_choice() -> void:
	if not InputMap.has_action("interact") or not Input.is_action_just_pressed("interact"):
		return
	if not _in_choice_range():
		return
	if _offer_open:
		accept_offer()
	else:
		walk_away()


func _in_choice_range() -> bool:
	var d := debtor()
	var a := _actor()
	if d == null or a == null:
		return false
	return a.global_position.distance_to(d.global_position) <= _n("choice_range", 4.0)


# ============================== THE HOOK =====================================
func _try_bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow):
		return
	_tow = _peer("tow_hook")
	if _tow == null:
		return
	for sig: String in ["hooked", "released"]:
		if _tow.has_signal(sig) and not _tow.is_connected(sig, _on_tow_event):
			_tow.connect(sig, _on_tow_event)


func _on_tow_event(_body: Variant = null) -> void:
	if state != State.IDLE:
		_evaluate_hook_state()


func _evaluate_hook_state() -> void:
	if _tow == null or not is_instance_valid(_tow) or _car == null:
		return
	var v: Variant = _tow.get("hooked_body")
	var cur: Node = v if (v is Node and is_instance_valid(v)) else null
	if cur == _prev_hooked:
		return
	var prev := _prev_hooked
	_prev_hooked = cur
	if cur == _car:
		_on_hook()
	elif prev == _car:
		_on_release()


## A frozen car cannot be towed (parked_cars' law) — the hook is what wakes it.
## Hooking also DISARMS the expiry: once the chain is on, the order is yours
## until you deliver it. A timer that deletes a car mid-haul is a bug wearing a
## deadline's clothes.
func _on_hook() -> void:
	state = State.HOOKED
	active = true
	_expire_armed = false
	if is_instance_valid(_car):
		_car.freeze = false
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.queue_free()
		_beacon = null
	_say(APP, _txt("app_hooked", "ORDER {id} ON THE HOOK.").format({"id": _id}))


func _on_release() -> void:
	if not is_instance_valid(_car):
		return
	var p := _car.global_position
	if absf(p.x - REPO.PAD_CENTER.x) <= REPO.PAD_HALF.x \
			and absf(p.z - REPO.PAD_CENTER.z) <= REPO.PAD_HALF.y and p.y < PAD_MAX_Y:
		_deliver()
	else:
		# Dropped short — a snapped chain, a bad corner, a change of heart. Still
		# the job, and the clock stays off; the beacon comes back where the car
		# actually lies so it is findable again from across downtown.
		state = State.PUSHED
		_raise_beacon(_ground_under_car())


# ============================== THE PAYOUT ===================================
## sedan 300 / pickup 450, x the haul bonus (up to +50 % at 400 m), x the rank
## multiplier (1.00 at ROOKIE to 1.60 at PARTNER). Floor $300, ceiling $1,080:
## an order always beats repo_board's flat $250-450 junker, because an order
## costs you a conversation.
func _deliver() -> void:
	var base := float(BASE_PAY.get(_cls, 300))
	var ref := maxf(_n("distance_ref_m", 400.0), 1.0)
	var bonus := 1.0 + _n("distance_bonus_max", 0.5) * clampf(_haul_m / ref, 0.0, 1.0)
	var pay := int(round(base * bonus * rank_mult()))
	_pay_money(pay, "ORDER %d" % _id)
	deliveries += 1
	quota_done += 1
	var paper := "CLEAN"
	if _bad:
		paper = "BAD — TAKEN"
		paper_taken += 1
		_pay_respect(int(_n("respect_taken", -3.0)), "TOOK THE PAPER")
	var was := rank
	sync_rank()
	_deliver_card(pay, paper)
	if rank > was:
		_promo_t = PROMO_DELAY   # the cards queue: one panel, two beats
	_close("delivered")


func _deliver_card(pay: int, paper: String) -> void:
	var kit := _peer("mission_kit")
	if kit == null or not kit.has_method("card"):
		return
	var nxt := next_rank_at()
	var progress := "%s  %d" % [rank_name(), deliveries]
	if nxt > 0:
		progress = "%s  %d/%d" % [rank_name(), deliveries, nxt]
	var rows: Array = [["PAY", "$%s" % _commas(pay)], ["RANK", progress], ["PAPER", paper]]
	var medal := "SILVER" if _heat_drawn else "GOLD"
	kit.call("card", "RECOVERED", "ORDER %d · %s · %s" % [_id, _who, _cls.to_upper()],
		rows, medal)


## PUBLIC (save_load): recompute `rank` from `deliveries`. Restore a save by
## setting `deliveries` and calling this, or set both and skip it — either way
## the two can never drift apart.
func sync_rank() -> void:
	var want := 1
	for i in RANK_AT.size():
		if deliveries >= RANK_AT[i]:
			want = i + 1
	rank = clampi(want, 1, RANK_NAMES.size())


## The app's only punishment in v1: one delivery of progress, never below the
## floor of a rank already earned. Walking away can cost you the next rank. It
## can never take back the one you have.
func _demote_one() -> void:
	var floor_at: int = RANK_AT[clampi(rank - 1, 0, RANK_AT.size() - 1)]
	deliveries = maxi(deliveries - 1, maxi(floor_at, 0))


func _promote_card() -> void:
	var nm := rank_name()
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("card"):
		var rows: Array = [["RATE", "x%.2f ON EVERY ORDER" % rank_mult()],
			["RECOVERED", str(deliveries)]]
		kit.call("card", "PROMOTED · %s" % nm, "LONGHORN WRECKER & RECOVERY", rows, "GOLD")
	_say(APP, _pick("promo_lines", "PROMOTION PROCESSED.").format({"rank": nm}))


# ============================== CLOSING ======================================
## Six minutes and nobody came. The app reassigns it to a contractor who wanted
## it, and the car stays exactly where its owner parked it.
func _expire() -> void:
	_say(APP, _txt("app_expire", "ORDER {id} EXPIRED.").format({"id": _id}))
	_close("expired")


## DELIVERED leaves with the story (the pad does not fill up). VOIDED and
## EXPIRED leave the car on its curb as scenery, because the whole point of
## walking away is that the car is still theirs. The debtor is never freed
## here — pedestrians.gd owns that life and despawns it by distance, and a
## person deleted in front of the player is its own kind of bug.
func _close(outcome: String) -> void:
	if outcome == "delivered":
		if is_instance_valid(_car):
			_car.queue_free()
		_car = null
	else:
		_abandon_car()
	_debtor = null
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.queue_free()
	_beacon = null
	state = State.IDLE
	active = false
	_prev_hooked = null
	_offer_open = false
	_met = false
	_line_t = 0.0
	_fight_t = 0.0
	_call_t = 0.0
	_expire_armed = true
	_gap_t = _n("order_gap", 40.0) + _rng.randf() * _n("gap_jitter", 20.0)
	order_closed.emit(outcome)


func _abandon_car() -> void:
	if not is_instance_valid(_car):
		_car = null
		return
	for g: String in ["mission_target", "repo_order", "towable"]:
		if _car.is_in_group(g):
			_car.remove_from_group(g)
	if _n("expire_unfreeze", 1.0) > 0.5:
		_car.freeze = false
	_abandoned.append(_car)
	_car = null


## Runs in every state, including IDLE: the deferred promotion card, and the
## abandoned-car sweep. Scenery 300 m behind you is a memory leak with a paint
## job — checked every 1.5 s, and only while there is anything to check.
func _tick_background(delta: float) -> void:
	if _promo_t > 0.0:
		_promo_t -= delta
		if _promo_t <= 0.0:
			_promote_card()
	if _abandoned.is_empty():
		return
	_sweep_t -= delta
	if _sweep_t > 0.0:
		return
	_sweep_t = SWEEP_EVERY
	var a := _actor()
	var far := _n("despawn_m", 300.0)
	var keep: Array[RigidBody3D] = []
	for b in _abandoned:
		if not is_instance_valid(b):
			continue
		if a != null and a.global_position.distance_to(b.global_position) > far:
			b.queue_free()
			continue
		keep.append(b)
	_abandoned = keep


# ============================== PLUMBING =====================================
## Everything this system says goes through mission_kit (D-063): the app in
## Bolo Capital's push voice, and the debtor under their own name in caps.
## There is no named dispatcher and there never will be.
func _say(speaker: String, line: String, seconds := 0.0) -> void:
	var kit := _peer("mission_kit")
	if kit == null or not kit.has_method("say") or line == "":
		return
	kit.call("say", speaker, line, seconds if seconds > 0.0 else _n("line_seconds", 5.0))


func _pay_money(amount: int, reason: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", amount, reason)


func _pay_respect(amount: int, reason: String) -> void:
	if amount == 0:
		return
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_respect"):
		repo.call("add_respect", amount, reason)


func _player_vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


func _actor() -> Node3D:
	if main_ref == null:
		return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var key := "character" if main_ref.get("on_foot") == true else "vehicle"
	var b: Variant = main_ref.get(key)
	if b is Node3D and is_instance_valid(b) and (b as Node).is_inside_tree():
		return b
	return null


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null
