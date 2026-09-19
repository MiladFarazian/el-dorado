extends Node
## PEDESTRIANS v1 — sidewalk crowds for downtown Dorado. Frozen-kinematic
## RigidBody3D mannequins (traffic.gd's proven pattern) walking the perimeter
## of the raised block slabs: a rounded-square loop inset 28 m from each block
## centre, feet on the 0.2 m slab top. They flee from anything fast bearing
## down on them, tumble as light bloodless debris when actually struck (player
## strikes cost heat and Respect, once per ped), dust themselves off after
## lying still, and despawn with distance. Threats target THE ACTOR (character
## on foot, vehicle otherwise) and gunfire (combat's shot_fired) scatters every
## ped within earshot. ENTIRELY INERT in smoke mode.
##
## ZONES (loop 14) put people in the districts too: data-driven polylines —
## Juárez Boulevard's two sidewalks, the Cliff's side streets and park, Harvest
## Hills' lumber lanes, Boone's showroom door, the fairgrounds gate — where the
## ped's "sidewalk" IS the polyline. Same ring, same interval, same states, same
## despawn; only the path and the costume bias differ. See ped_zones.json.

# ============================== TUNABLES =====================================
const RNG_SEED := 90210; const PED_COUNT := 16   # seed; crowd size maintained
const SPAWN_RING := Vector2(60.0, 200.0)  # block-centre band around player (m)
const SPAWN_MIN_DIST := 50.0              # ped itself never pops closer (m)
const DESPAWN_DIST := 260.0; const SPAWN_INTERVAL := 0.3; const SPAWN_TRIES := 10
const THREAT_REFRESH := 0.3               # threat-set rescan cadence (s)
const GRACE := 1.0                        # no knockdowns in a ped's first second
const SLAB_TOP := 0.2                     # downtown slab surface height (m)
const PED_HALF := 0.875                   # half of the 1.75 m collider
const COLLIDER_SIZE := Vector3(0.5, 1.75, 0.35); const PED_MASS := 80.0
const WALK_SPEED := Vector2(1.2, 1.9)     # per-ped seeded stroll (m/s)
const PATH_INSET := 28.0; const CORNER_R := 3.0  # loop inset; corner arc radius
const BLOCK_CLAMP := 29.0                 # fleeing peds stay on the slab (m)
const FLEE_RADIUS := 8.0; const FLEE_CLOSING := 6.0  # threat range / speed (m, m/s)
const FLEE_SPEED := 4.0; const FLEE_TIME := Vector2(1.7, 2.3)  # panic run (m/s, s)
const ZIG_RATE := 7.0; const ZIG_AMP := 0.55  # panicked zigzag (rad/s, rad)
const KNOCK_RADIUS := 1.7; const KNOCK_CLOSING := 4.0  # pre-impact unfreeze
const GUN_PANIC_RADIUS := 30.0; const GUN_PANIC_TIME := 4.0  # gunshot scatter
const HOT_HEAT := 2; const HOT_RADIUS := 12.0  # D-057: a wanted man clears the sidewalk
# --- Brawlers (D-058). A share of walkers are BRAVE: hit one with a fist and he
# squares up instead of running — closes to reach, throws a punch on a windup
# you can see, keeps at it until he is put down or you leave. His punch asks
# melee.gd whether a guard is up (half) or JUST came up (nothing, and he
# staggers — fair game for the counter). The rest of the sidewalk runs, which
# is also new: a punched coward used to just stand there.
const BRAVE_CHANCE := 0.35; const BRAVE_SEED := 0xB4A7E  # own stream: costumes stay seeded
const BRAWL_REACH := 1.3           # m: he stops here and swings
const BRAWL_SPEED := 2.6           # m/s closing on Book
const PUNCH_INTERVAL := 1.1        # s between punches
const PUNCH_WINDUP := 0.35         # s of visible lean-in before the punch lands
const PUNCH_DAMAGE := 6.0          # hp; halved by a guard, zero on a perfect one
const PUNCH_TRAUMA := 0.22
const PUNCH_HIT_RANGE := 1.8       # m: Book inside this when it lands takes it
const STUN_TIME := 1.3             # s a countered brawler stands stunned
const BRAWL_GIVE_UP := 9.0         # m: Book this far away ends the fight
const BRAWL_TIME := 10.0           # s of brawling, then he thinks better of it
const WINDUP_LEAN := 0.25          # m he steps in over the windup
# --- Followers (D-063): a mission spawns a walker who goes to a node and stands
# there — the debtor who comes out of the house. Self-despawns on its clock or
# when the node gets away.
const FOLLOW_SPEED := 2.4; const FOLLOW_STOP := 2.8; const FOLLOW_GIVE_UP := 40.0
const HIT_CARRY := 0.6; const HIT_POP := 2.2  # striker velocity share; up-fling
const CHARGE_MIN_SPEED := 2.0             # parked-car nudges are not a crime
const HEAT_ON_HIT := 1; const RESPECT_ON_HIT := -2  # player-strike penalties
const STILL_SPEED := 0.4; const GETUP_TIME := 8.0  # "nearly still" gate; lie time
# Downtown grid per scripts/world/greybox_city.gd: 8x6 blocks, centres at
# (150 + 86*i, 90 + 86*j), 60 m slabs whose TOP surface is y = 0.2.
const GRID_COLS := 8; const GRID_ROWS := 6
const BLOCK_ORIGIN := Vector2(150.0, 90.0); const BLOCK_PITCH := 86.0
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)  # protected: NEVER place in
# Rounded-square loop: 4 straights + 4 quarter arcs, walked by path coord s.
const PATH_STRAIGHT := 2.0 * (PATH_INSET - CORNER_R)
const PATH_ARC := 0.5 * PI * CORNER_R
const PATH_SEG := PATH_STRAIGHT + PATH_ARC
const PATH_PERIM := 4.0 * PATH_SEG
const DIRS: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
const P0S: Array[Vector2] = [  # each side's straight start, relative to centre
	Vector2(-(PATH_INSET - CORNER_R), -PATH_INSET),
	Vector2(PATH_INSET, -(PATH_INSET - CORNER_R)),
	Vector2(PATH_INSET - CORNER_R, PATH_INSET),
	Vector2(-PATH_INSET, PATH_INSET - CORNER_R)]

enum { WALK, FLEE, DOWN, BRAWL, IDLE, FOLLOW }   # IDLE: a spawned brawler waiting (probe); FOLLOW: a mission walker

const FACTORY := preload("res://scripts/world/character_factory.gd")
## SKINNED-BODY PROOF OF CONCEPT — inert unless `--skinned` is on the command
## line. `character_factory` remains the shipping path and is not modified; only
## `build()` is redirected, because `animate()` / `aim_pose()` / the rig dict are
## contract-identical between the two and the skinned body delegates to the
## factory's animator anyway.
const SKINNED := preload("res://scripts/world/skinned_character.gd")
static func _body_script() -> GDScript:
	return FACTORY if OS.get_cmdline_user_args().has("--factory") else SKINNED   # D-050: skinned is the default; --factory is the M22 body


# --- ZONES (loop 14): people where the new districts are. A zone is a POLYLINE
# of sidewalk points that IS its peds' loop — they stroll it exactly the way a
# downtown ped walks a block's rounded square, and every other behaviour (flee,
# brawl, knockdown, gunfire panic, despawn) is the shared code below. The ring,
# the interval and the try budget are the SHARED ones, so a zone the player is
# nowhere near simply never qualifies. Data: ped_zones.json.
# EVERY zone draw comes off _zone_rng — the downtown spawner's stream, and the
# smoke line with it, must not move by a single call.
const ZONES_PATH := "res://data/mechanics/ped_zones.json"
const ZONE_SEED := 0x2ED20E
const ZONE_TRIES := 10          # zone spawn attempts per frame (mirrors SPAWN_TRIES)
const ZONE_OUTFIT_TRIES := 24   # costume rolls spent hunting a zone's archetype
const ZONE_NEAR_PAD := 20.0     # slack on the near-list radius test (m)
const ZONE_MIN_DIST := SPAWN_MIN_DIST   # per-zone `min_dist` default
# Outfit / hat names as the data file spells them. Compile-time constants, so a
# typo in the factory's enum is a parse error rather than a silent CASUAL.
const OUTFIT_BY_NAME := {
	"CASUAL": FACTORY.Outfit.CASUAL, "WESTERN": FACTORY.Outfit.WESTERN,
	"WORKER": FACTORY.Outfit.WORKER, "OFFICE": FACTORY.Outfit.OFFICE,
	"SERVICE": FACTORY.Outfit.SERVICE, "STREET": FACTORY.Outfit.STREET,
	"SCRUBS": FACTORY.Outfit.SCRUBS, "GAMEDAY": FACTORY.Outfit.GAMEDAY}
const HAT_BY_NAME := {
	"NONE": FACTORY.Hat.NONE, "CAP": FACTORY.Hat.CAP, "COWBOY": FACTORY.Hat.COWBOY,
	"FLAT_BRIM": FACTORY.Hat.FLAT_BRIM, "HARD_HAT": FACTORY.Hat.HARD_HAT,
	"BEANIE": FACTORY.Hat.BEANIE}
const HARD_HAT_COLORS: Array[Color] = [  # the factory's own three, so a forced lid matches a rolled one
	Color(0.92, 0.78, 0.10), Color(0.90, 0.90, 0.88), Color(0.90, 0.42, 0.08)]

# ============================== STATE ========================================
var main_ref: Node = null
var _rng := RandomNumberGenerator.new()
var _peds: Array[Dictionary] = []
var _threats: Array[Node3D] = []  # membership rescanned every 0.3 s
var _heat := 0                     # police.heat, cached at the threat refresh
var _brave_rng := RandomNumberGenerator.new()  # brave draws, off the costume stream
var _spawn_cd := 0.0; var _threat_cd := 0.0; var _spawned := 0
var _combat_bound := false  # combat.shot_fired connected (peer binds lazily)
var _copfire_bound := false  # police_gunfire.shot_fired connected likewise
var _footcop_bound := false  # foot_cops.shot_fired connected likewise (M14)
var _pp_pos := Vector3.ZERO; var _pp_head := Vector3.ZERO  # _path_point outputs
var _clear_cells: Array[Vector2i] = []  # tower-free blocks: lots + the Trust plaza
var _zones: Array[Dictionary] = []   # district sidewalks from ped_zones.json
var _zone_rng := RandomNumberGenerator.new()  # zone draws: OFF the downtown stream
var _zone_near: Array[int] = []      # zone indices inside the ring, refreshed at 0.3 s
var _zone_live: Array[int] = []      # live peds per zone, tallied at spawn time
var _zn_pos := Vector2.ZERO; var _zn_off := 0.0  # _zone_nearest outputs

func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED; _brave_rng.seed = BRAVE_SEED
	_zone_rng.seed = ZONE_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return  # smoke gate: inert
	_build_clear_cells(); _load_zones()

## Tower quadrants reach up to 30 m from block centre — through the 28 m
## sidewalk ring — so peds only walk tower-free blocks: parking lots (city
## registry) plus Cattleman's Trust plaza (its lone 26 m tower reaches 13 m).
func _build_clear_cells() -> void:
	_clear_cells.clear()
	var city: Variant = main_ref.get("city")
	if city is Node and is_instance_valid(city) and (city as Node).has_method("get_lot_cells"):
		var got: Variant = (city as Node).call("get_lot_cells")
		if got is Array:
			for v: Variant in got:
				if v is Vector2i: _clear_cells.append(v)
	var gc: Variant = (city as Node).get("GIANT_CELL") if city is Node and is_instance_valid(city) else null
	_clear_cells.append(gc if gc is Vector2i else Vector2i(3, 2))

## ZONE DATA. Read once, at setup, and never in smoke mode (this system's
## processing is already off by then). A malformed zone is dropped, not fatal:
## the districts go quiet, downtown is untouched.
func _load_zones() -> void:
	_zones.clear(); _zone_live.clear(); _zone_near.clear()
	var f := FileAccess.open(ZONES_PATH, FileAccess.READ)
	if f == null: return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary): return
	var list: Variant = (parsed as Dictionary).get("zones")
	if not (list is Array): return
	for v: Variant in (list as Array):
		if v is Dictionary:
			var z := _zone_from(v as Dictionary)
			if not z.is_empty(): _zones.append(z)
	_zone_live.resize(_zones.size())

## One zone from data. The polyline is precomputed into segment starts, unit
## directions and lengths — walking it is then one subtraction per segment —
## plus a bounding circle for the near test. {} when the shape is unusable.
func _zone_from(d: Dictionary) -> Dictionary:
	var raw: Variant = d.get("pts")
	if not (raw is Array): return {}
	var pts := PackedVector2Array()
	for v: Variant in (raw as Array):
		if v is Array and (v as Array).size() >= 2:
			pts.append(Vector2(float((v as Array)[0]), float((v as Array)[1])))
	if pts.size() < 2: return {}
	var loop := bool(d.get("loop", false))
	var dirs := PackedVector2Array(); var lens := PackedFloat32Array(); var total := 0.0
	for i in (pts.size() if loop else pts.size() - 1):
		var seg := pts[(i + 1) % pts.size()] - pts[i]
		var seg_len := seg.length()
		if seg_len < 0.01: return {}   # a doubled point would divide by zero
		dirs.append(seg / seg_len); lens.append(seg_len); total += seg_len
	var mid := Vector2.ZERO
	for p: Vector2 in pts: mid += p
	mid /= float(pts.size())
	var rad := 0.0
	for p: Vector2 in pts: rad = maxf(rad, mid.distance_to(p))
	var z := {"name": String(d.get("name", "zone")), "pts": pts, "dirs": dirs,
		"lens": lens, "len": total, "loop": loop,
		"width": maxf(float(d.get("width", 1.2)), 0.3),
		"cap": maxi(int(d.get("cap", 2)), 0), "y": float(d.get("y", 0.05)),
		"min_dist": float(d.get("min_dist", ZONE_MIN_DIST)),
		"hat": int(HAT_BY_NAME.get(String(d.get("hat", "")), -1)),
		"center": mid, "radius": rad}
	_zone_mix(z, d)
	return z

## The outfit mix: parallel code/weight arrays plus their sum, so picking one
## is a single randf against a running total. JSON key order is insertion
## order, so the same file always weights the same way.
func _zone_mix(z: Dictionary, d: Dictionary) -> void:
	var codes := PackedInt32Array(); var wts := PackedFloat32Array(); var wsum := 0.0
	var mix: Variant = d.get("outfits")
	if mix is Dictionary:
		for k: Variant in (mix as Dictionary):
			var code := int(OUTFIT_BY_NAME.get(String(k), -1))
			var w := float((mix as Dictionary)[k])
			if code >= 0 and w > 0.0:
				codes.append(code); wts.append(w); wsum += w
	z["ocodes"] = codes; z["owts"] = wts; z["owsum"] = wsum

func _physics_process(delta: float) -> void:
	if main_ref == null: return
	var pv := _player()
	_threat_cd -= delta
	if _threat_cd <= 0.0:
		_threat_cd = THREAT_REFRESH; _refresh_threats(pv); _bind_combat()
		_refresh_zone_near(pv)
	_validate(pv, delta)
	_spawn_cd = maxf(_spawn_cd - delta, 0.0)
	# Downtown first and UNCHANGED (its draw order is the smoke line); the
	# districts get the frame only when no block qualified, which is exactly
	# what happens the moment the player leaves the grid.
	if pv != null and _spawn_cd <= 0.0 and _peds.size() < PED_COUNT \
			and (_try_spawn(pv.global_position) or _try_zone_spawn(pv.global_position)):
		_spawn_cd = SPAWN_INTERVAL
	for ped in _peds:
		_update_ped(ped, delta)

# ============================== POPULATION ===================================
func _validate(pv: Node3D, delta: float) -> void:
	for i in range(_peds.size() - 1, -1, -1):
		var ped := _peds[i]
		var bv: Variant = ped["body"]   # D-068: validity before the cast — 4.7 errors on casting a freed object
		if not is_instance_valid(bv) or not (bv as Node).is_inside_tree():
			_peds.remove_at(i); continue
		var body := bv as RigidBody3D
		ped["age"] = float(ped["age"]) + delta
		if pv != null and body.global_position.distance_to(pv.global_position) > DESPAWN_DIST:
			body.queue_free(); _peds.remove_at(i)  # covers never-settling debris too

## Seeded spawn: a block whose centre sits in the 60-200 m ring, a random path
## coord on its loop, >= 50 m from the player, never in the protected corridor.
func _try_spawn(ppos: Vector3) -> bool:
	for _a in SPAWN_TRIES:
		var c: Vector2
		if not _clear_cells.is_empty():
			var cell := _clear_cells[_rng.randi_range(0, _clear_cells.size() - 1)]
			c = Vector2(BLOCK_ORIGIN.x + BLOCK_PITCH * float(cell.x),
				BLOCK_ORIGIN.y + BLOCK_PITCH * float(cell.y))
		else:  # no city registry: any block (v1 clipping accepted)
			c = Vector2(
				BLOCK_ORIGIN.x + BLOCK_PITCH * float(_rng.randi_range(0, GRID_COLS - 1)),
				BLOCK_ORIGIN.y + BLOCK_PITCH * float(_rng.randi_range(0, GRID_ROWS - 1)))
		var bd := Vector2(c.x - ppos.x, c.y - ppos.z).length()
		if bd < SPAWN_RING.x or bd > SPAWN_RING.y: continue
		var s := _rng.randf_range(0.0, PATH_PERIM)
		_path_point(c, s)
		if CORRIDOR.has_point(Vector2(_pp_pos.x, _pp_pos.z)): continue
		if Vector2(_pp_pos.x - ppos.x, _pp_pos.z - ppos.z).length() < SPAWN_MIN_DIST: continue
		_make_ped(c, s); return true
	return false

func _make_ped(c: Vector2, s: float) -> void:
	var body := RigidBody3D.new()
	_spawned += 1; body.name = "Ped%d" % _spawned
	body.mass = PED_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	# 8, not 2: speculative contacts with the slab exhaust a small budget and
	# dynamic-body contacts then never report (hard-learned in traffic.gd).
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("pedestrian")  # NOT "towable" — we do not tow people
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = COLLIDER_SIZE; col.shape = shape; body.add_child(col)
	# M9: full factory people (legs, arms, hats, the works). Costume draws come
	# from this system's own rng — deterministic per run; collider unchanged.
	var rig: Dictionary = _body_script().build(body, FACTORY.random_config(_rng), -PED_HALF)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	var wdir := -1.0 if _rng.randf() < 0.5 else 1.0  # loop direction
	_path_point(c, s); _place(body, _pp_head * wdir, _pp_pos)
	body.body_entered.connect(_on_contact.bind(body))
	_peds.append({
		"body": body, "center": c, "s": s, "wdir": wdir, "rig": rig,
		"speed": _rng.randf_range(WALK_SPEED.x, WALK_SPEED.y),  # seeded stroll
		"state": WALK, "age": 0.0, "charged": false, "still_t": 0.0,
		"flee_t": 0.0, "flee_dir": Vector3.FORWARD, "zig_t": 0.0,
		"brave": _brave_rng.randf() < BRAVE_CHANCE, "punch_t": 0.0, "brawl_t": 0.0,
		"stun_t": 0.0, "bpos": Vector3.ZERO, "moving": false, "spawned": false})

# ============================== ZONE POPULATION ==============================
## Which zones could possibly qualify right now. Rebuilt on the threat cadence
## rather than per frame: when the player is downtown (or on the freeway, or
## anywhere else), the list is empty and a zone spawn attempt costs nothing.
func _refresh_zone_near(pv: Node3D) -> void:
	_zone_near.clear()
	if pv == null: return
	var p := Vector2(pv.global_position.x, pv.global_position.z)
	for i in _zones.size():
		var z := _zones[i]
		var reach := float(z["radius"]) + SPAWN_RING.y + ZONE_NEAR_PAD
		if p.distance_to(z["center"] as Vector2) <= reach:
			_zone_near.append(i)

## Seeded zone spawn, same shape as _try_spawn: a near zone with room under its
## cap, a random arc coord on its polyline, inside the ring, never closer than
## the zone's min_dist, NEVER in the protected corridor. Own RNG throughout.
func _try_zone_spawn(ppos: Vector3) -> bool:
	if _zone_near.is_empty(): return false
	_tally_zones()
	for _a in ZONE_TRIES:
		var zi := _zone_near[_zone_rng.randi_range(0, _zone_near.size() - 1)]
		var z := _zones[zi]
		if _zone_live[zi] >= int(z["cap"]): continue
		var s := _zone_rng.randf_range(0.0, float(z["len"]))
		_zone_point(z, s)
		if CORRIDOR.has_point(Vector2(_pp_pos.x, _pp_pos.z)): continue
		var d := Vector2(_pp_pos.x - ppos.x, _pp_pos.z - ppos.z).length()
		if d < float(z["min_dist"]) or d > SPAWN_RING.y: continue
		_make_zone_ped(zi, s); return true
	return false

func _tally_zones() -> void:
	_zone_live.fill(0)
	for ped in _peds:
		var zi := int(ped.get("zone", -1))
		if zi >= 0 and zi < _zone_live.size(): _zone_live[zi] += 1

## PUBLIC (probe): live peds belonging to the named zone. `zone_name` rather
## than `name`: a parameter called `name` shadows Node.name.
func zone_count(zone_name: String) -> int:
	var n := 0
	for ped in _peds:
		var zi := int(ped.get("zone", -1))
		if zi < 0 or zi >= _zones.size(): continue
		if not is_instance_valid(ped["body"]): continue
		if String(_zones[zi]["name"]) == zone_name: n += 1
	return n

## PUBLIC (probe): the zone's polyline length in metres, 0.0 when unknown.
func zone_length(zone_name: String) -> float:
	for z in _zones:
		if String(z["name"]) == zone_name: return float(z["len"])
	return 0.0

## A zone walker. Deliberately NOT _make_ped: that function's draw order is the
## downtown stream and nothing here may touch it. Everything below rolls off
## _zone_rng, and the ped carries its zone index for the path code.
func _make_zone_ped(zi: int, s: float) -> void:
	var z := _zones[zi]
	var body := RigidBody3D.new()
	_spawned += 1; body.name = "Ped%d" % _spawned
	body.mass = PED_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("pedestrian")  # NOT "towable" — we do not tow people
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = COLLIDER_SIZE; col.shape = shape; body.add_child(col)
	var rig: Dictionary = _body_script().build(body, _zone_config(z), -PED_HALF)
	add_child(body)
	var wdir := -1.0 if _zone_rng.randf() < 0.5 else 1.0
	_zone_point(z, s); _place(body, _pp_head * wdir, _pp_pos)
	body.body_entered.connect(_on_contact.bind(body))
	_peds.append({
		"body": body, "center": Vector2(_pp_pos.x, _pp_pos.z), "s": s,
		"wdir": wdir, "rig": rig, "zone": zi,
		"speed": _zone_rng.randf_range(WALK_SPEED.x, WALK_SPEED.y),
		"state": WALK, "age": 0.0, "charged": false, "still_t": 0.0,
		"flee_t": 0.0, "flee_dir": Vector3.FORWARD, "zig_t": 0.0,
		"brave": _zone_rng.randf() < BRAVE_CHANCE, "punch_t": 0.0, "brawl_t": 0.0,
		"stun_t": 0.0, "bpos": Vector3.ZERO, "moving": false, "spawned": false})

## The zone's outfit mix, biased the only way the factory allows. FACTORY
## .random_config() takes an rng and NOTHING else — there is no outfit override
## and character_factory.gd is not ours to edit this round — so we draw the
## archetype from the zone's weight table and then roll costumes until one comes
## up in it. Budgeted: on exhaustion the sidewalk simply gets a visitor.
func _zone_config(z: Dictionary) -> Dictionary:
	var cfg: Dictionary = FACTORY.random_config(_zone_rng)
	var want := _zone_outfit(z)
	if want >= 0:
		for _t in ZONE_OUTFIT_TRIES:
			if int(cfg.get("outfit", -1)) == want: break
			cfg = FACTORY.random_config(_zone_rng)
	# A forced lid only lands on the archetype that wears one — a hard hat on a
	# man in a polo is a costume error, not a construction site.
	var hat := int(z.get("hat", -1))
	if hat >= 0 and int(cfg.get("outfit", -1)) == FACTORY.Outfit.WORKER:
		cfg["hat"] = hat
		if hat == FACTORY.Hat.HARD_HAT:
			cfg["hat_color"] = HARD_HAT_COLORS[_zone_rng.randi_range(0, HARD_HAT_COLORS.size() - 1)]
	return cfg

func _zone_outfit(z: Dictionary) -> int:
	var codes: PackedInt32Array = z["ocodes"]
	if codes.is_empty(): return -1
	var wts: PackedFloat32Array = z["owts"]
	var roll := _zone_rng.randf() * float(z["owsum"])
	for i in codes.size():
		roll -= wts[i]
		if roll <= 0.0: return codes[i]
	return codes[codes.size() - 1]

# ============================== BEHAVIOUR ====================================
func _update_ped(ped: Dictionary, delta: float) -> void:
	var bv: Variant = ped["body"]
	if not is_instance_valid(bv) or not (bv as Node).is_inside_tree(): return
	var body := bv as RigidBody3D
	match int(ped["state"]):
		DOWN: _update_down(ped, body, delta)
		FLEE:
			if not _check_threats(ped, body): _update_flee(ped, body, delta)
		WALK:
			if not _check_threats(ped, body): _update_walk(ped, body, delta)
		BRAWL: _update_brawl(ped, body, delta)
		FOLLOW: _update_follow(ped, body, delta)
	# M10 walk cycle. Kinematic peds are moved by transform, so their gait
	# speed is the scripted one (strolling, or the panic run), not velocity.
	# A downed ped is loose physics: the rig freezes and it tumbles as a body.
	var st := int(ped["state"])
	if st == DOWN: return   # D-059: a tumbling body keeps the pose it fell with; the idle would breathe on the pavement
	var gait := 0.0
	if st == WALK: gait = float(ped["speed"])
	elif st == FLEE: gait = FLEE_SPEED
	elif st == BRAWL and bool(ped["moving"]): gait = BRAWL_SPEED
	elif st == FOLLOW and bool(ped["moving"]): gait = FOLLOW_SPEED
	FACTORY.animate(ped["rig"] as Dictionary, gait, delta, st != DOWN)
	if st == BRAWL: _brawl_arms(ped, delta)   # after animate: the last writer wins the frame

## D-060: the brawler's hands are up and the punch is an ARM, not just a lean.
## Same joint grammar as melee.gd (+x swings a limb forward): both fists up in a
## guard between punches; over the windup the right arm cocks back, at impact it
## drives through, then it recovers to the guard. Stunned: the arms drop.
func _brawl_arms(ped: Dictionary, delta: float) -> void:
	var rig: Dictionary = ped["rig"]
	if rig.is_empty(): return
	var k := 1.0 - exp(-22.0 * delta)
	var pt := float(ped["punch_t"])
	var stunned := float(ped["stun_t"]) > 0.0
	var sh_r := 0.95; var el_r := 1.85; var sh_l := 0.85; var el_l := 1.95   # the guard
	if stunned:
		sh_r = 0.25; el_r = 0.45; sh_l = 0.25; el_l = 0.45                    # rocked: arms sag
	elif pt <= PUNCH_WINDUP:
		var w := 1.0 - clampf(pt / PUNCH_WINDUP, 0.0, 1.0)                  # 0 cocked .. 1 landing
		sh_r = lerpf(0.30, 1.60, w); el_r = lerpf(2.10, 0.15, w)             # cock back, drive through
	for pair: Array in [["sh_1", sh_r], ["el_1", el_r], ["sh_0", sh_l], ["el_0", el_l]]:
		var j: Variant = rig.get(pair[0])
		if j is Node3D:
			(j as Node3D).rotation.x = lerp_angle((j as Node3D).rotation.x, float(pair[1]), k)

## Distance math only against the cached threat set — NO raycasts. Positions
## and velocities read live off the cached body refs; membership is the part
## rescanned every 0.3 s. Returns true when the ped got knocked down.
func _check_threats(ped: Dictionary, body: RigidBody3D) -> bool:
	var pos := body.global_position
	for t in _threats:
		if not is_instance_valid(t) or not t.is_inside_tree() or t == body: continue
		var sep := pos - t.global_position; var d := sep.length()
		if d < 0.01 or d > FLEE_RADIUS: continue
		var closing := _actor_velocity(t).dot(sep / d)  # speed toward the ped
		if d < KNOCK_RADIUS and closing > KNOCK_CLOSING:
			_knockdown(ped, body, t); return true  # unfreeze BEFORE the impact
		if closing > FLEE_CLOSING and int(ped["state"]) == WALK:
			_start_flee(ped, body, t)
		elif int(ped["state"]) == WALK and _heat >= HOT_HEAT and d < HOT_RADIUS and t.is_in_group("player"):
			_flee_away(ped, sep / d)  # world memory, the cheap kind: they know who you are
	return false

# ============================== BRAWLING (D-058) =============================
## PUBLIC (melee): a fist landed and did not put him down. Brave → he squares
## up; the rest bolt. Nothing happens to a man already down or already fighting.
func on_melee_hit(body: RigidBody3D, striker: Node) -> void:
	var ped := _find(body)
	if ped.is_empty(): return
	var st := int(ped["state"])
	if st == DOWN or st == BRAWL: return
	if bool(ped.get("brave", false)):
		_start_brawl(ped, body)
	elif striker is Node3D:
		_flee_away(ped, body.global_position - (striker as Node3D).global_position)

func _start_brawl(ped: Dictionary, body: RigidBody3D) -> void:
	ped["state"] = BRAWL; ped["punch_t"] = PUNCH_INTERVAL; ped["brawl_t"] = 0.0
	ped["stun_t"] = 0.0; ped["bpos"] = body.global_position; ped["moving"] = false

func _end_brawl(ped: Dictionary, body: RigidBody3D) -> void:
	if bool(ped.get("spawned", false)):
		ped["state"] = IDLE; return
	var pv := _player()
	_flee_away(ped, body.global_position - pv.global_position if pv != null else Vector3.FORWARD)

## Face Book, close to reach, lean in over the windup, swing. A stunned man
## stands there. Book too far, or too long at it, and he thinks better of it.
func _update_brawl(ped: Dictionary, body: RigidBody3D, delta: float) -> void:
	var pv := _player()
	ped["brawl_t"] = float(ped["brawl_t"]) + delta
	ped["moving"] = false
	if not (pv is CharacterBody3D) or float(ped["brawl_t"]) > BRAWL_TIME \
			or pv.global_position.distance_to(body.global_position) > BRAWL_GIVE_UP:
		_end_brawl(ped, body); return
	if float(ped["stun_t"]) > 0.0:
		ped["stun_t"] = float(ped["stun_t"]) - delta
		return
	var bpos: Vector3 = ped["bpos"]
	var sep := pv.global_position - bpos; sep.y = 0.0
	var d := sep.length()
	var head := sep.normalized() if d > 0.05 else Vector3.FORWARD
	if d > BRAWL_REACH + 0.15:
		bpos += head * minf(BRAWL_SPEED * delta, d - BRAWL_REACH); ped["moving"] = true
		ped["bpos"] = bpos
	ped["punch_t"] = float(ped["punch_t"]) - delta
	var pt := float(ped["punch_t"])
	var lean := head * WINDUP_LEAN * (1.0 - clampf(pt / PUNCH_WINDUP, 0.0, 1.0)) if pt <= PUNCH_WINDUP else Vector3.ZERO
	_place(body, head, bpos + lean)
	if pt <= 0.0:
		_ped_punch(ped, pv as CharacterBody3D, body, d)
		ped["punch_t"] = PUNCH_INTERVAL

func _ped_punch(ped: Dictionary, ch: CharacterBody3D, body: RigidBody3D, d: float) -> void:
	if d > PUNCH_HIT_RANGE: return              # swung at air
	var melee := _peer("melee")
	if melee != null and melee.has_method("perfect_guard") and melee.call("perfect_guard") == true:
		ped["stun_t"] = STUN_TIME                # countered: he staggers, fair game
		if melee.has_method("on_blocked"): melee.call("on_blocked", true)
		return
	var mult := 1.0
	if melee != null and melee.has_method("guard_damage_mult"):
		mult = float(melee.call("guard_damage_mult"))
	if ch.has_method("take_damage"): ch.call("take_damage", PUNCH_DAMAGE * mult, body)
	if mult < 1.0:
		if melee != null and melee.has_method("on_blocked"): melee.call("on_blocked", false)
	elif melee != null and melee.has_method("play_impact"):
		melee.call("play_impact", PUNCH_TRAUMA)

## PUBLIC (melee): a stunned brawler goes down to the next hit.
func is_stunned(body: RigidBody3D) -> bool:
	var ped := _find(body)
	return not ped.is_empty() and int(ped["state"]) == BRAWL and float(ped["stun_t"]) > 0.0

## PUBLIC (probe): the state enum value, or -1.
func state_of(body: RigidBody3D) -> int:
	var ped := _find(body)
	return int(ped["state"]) if not ped.is_empty() else -1

## PUBLIC (probe): seconds until his next punch lands, INF when not brawling.
func punch_in(body: RigidBody3D) -> float:
	var ped := _find(body)
	if ped.is_empty() or int(ped["state"]) != BRAWL or float(ped["stun_t"]) > 0.0: return INF
	return float(ped["punch_t"])

## PUBLIC (missions): a walker who goes to `target` and stands at arm's length
## for `seconds`, then leaves. Returns the body (group "follower").
func spawn_follower_at(pos: Vector3, facing: Vector3, target: Node3D, seconds: float) -> RigidBody3D:
	var body := spawn_brawler_at(pos, facing)
	body.add_to_group("follower")
	var ped := _find(body)
	if not ped.is_empty():
		ped["state"] = FOLLOW; ped["brave"] = false
		ped["follow"] = target; ped["follow_t"] = seconds; ped["bpos"] = pos
	return body

func _update_follow(ped: Dictionary, body: RigidBody3D, delta: float) -> void:
	var t: Variant = ped.get("follow")
	ped["follow_t"] = float(ped.get("follow_t", 0.0)) - delta
	ped["moving"] = false
	var bpos: Vector3 = ped["bpos"]
	# D-068: validity FIRST — `is` on a freed instance is an error in 4.7, and a
	# follower's target is freed every time the player's rig is swapped (TAB, a
	# purchase, a recovery).
	if not is_instance_valid(t) or not (t is Node3D) or float(ped["follow_t"]) <= 0.0 \
			or (t as Node3D).global_position.distance_to(bpos) > FOLLOW_GIVE_UP:
		body.queue_free()   # _validate drops the freed entry
		return
	var sep := (t as Node3D).global_position - bpos; sep.y = 0.0
	var d := sep.length()
	var head := sep.normalized() if d > 0.05 else Vector3.FORWARD
	if d > FOLLOW_STOP:
		bpos += head * minf(FOLLOW_SPEED * delta, d - FOLLOW_STOP); ped["moving"] = true
		ped["bpos"] = bpos
	_place(body, head, bpos)

## PUBLIC (probe/debug): a brave man standing at `pos` facing `facing`, waiting.
func spawn_brawler_at(pos: Vector3, facing: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	_spawned += 1; body.name = "Brawler%d" % _spawned
	body.mass = PED_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("pedestrian")
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = COLLIDER_SIZE; col.shape = shape; body.add_child(col)
	var rig: Dictionary = _body_script().build(body, FACTORY.random_config(_rng), -PED_HALF)
	add_child(body)
	_place(body, facing, pos)
	body.body_entered.connect(_on_contact.bind(body))
	_peds.append({"body": body, "center": Vector2(pos.x, pos.z), "s": 0.0, "wdir": 1.0, "rig": rig,
		"speed": 0.0, "state": IDLE, "age": GRACE + 1.0, "charged": false, "still_t": 0.0,
		"flee_t": 0.0, "flee_dir": Vector3.FORWARD, "zig_t": 0.0,
		"brave": true, "punch_t": 0.0, "brawl_t": 0.0, "stun_t": 0.0, "bpos": pos,
		"moving": false, "spawned": true})
	return body

## Straight away from a threat that need not be moving (a wanted man, a horn).
func _flee_away(ped: Dictionary, away: Vector3) -> void:
	away.y = 0.0
	ped["state"] = FLEE; ped["flee_dir"] = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	ped["flee_t"] = _rng.randf_range(FLEE_TIME.x, FLEE_TIME.y)
	ped["zig_t"] = _rng.randf_range(0.0, TAU)

func _update_walk(ped: Dictionary, body: RigidBody3D, delta: float) -> void:
	var wdir := float(ped["wdir"])
	var zi := _zone_of(ped)
	var step := wdir * float(ped["speed"]) * delta
	if zi < 0:
		ped["s"] = wrapf(float(ped["s"]) + step, 0.0, PATH_PERIM)
	else:
		var total := float(_zones[zi]["len"])
		var s := float(ped["s"]) + step
		if bool(_zones[zi]["loop"]):
			s = wrapf(s, 0.0, total)
		elif s < 0.0 or s > total:   # an open sidewalk ends: he turns and walks back
			wdir = -wdir; ped["wdir"] = wdir
			s = clampf(s, 0.0, total)
		ped["s"] = s
	_point_at(ped, float(ped["s"]))
	_place(body, _pp_head * wdir, _pp_pos)  # face along travel

## PUBLIC (vehicle_audio): the player leaned on the horn. Walkers ahead of the
## grille inside `radius` bolt the way they would from a closing car — same flee,
## same zigzag — without anyone having to be about to die first. A parked car
## has no travel direction, so the split is off its FACING instead.
func honk_at(src: Node3D, radius: float) -> void:
	if not is_instance_valid(src) or not src.is_inside_tree():
		return
	var fwd := -src.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		return
	fwd = fwd.normalized()
	for ped in _peds:
		if int(ped["state"]) != WALK:
			continue
		var bv: Variant = ped["body"]   # D-068: validity before the cast, always
		if not is_instance_valid(bv):
			continue
		var body := bv as RigidBody3D
		var sep := body.global_position - src.global_position
		sep.y = 0.0
		var d := sep.length()
		if d > radius or d < 0.01 or fwd.dot(sep / d) < 0.2:
			continue
		if _actor_velocity(src).length() > 1.0:
			_start_flee(ped, body, src)
			continue
		var perp := Vector3(-fwd.z, 0.0, fwd.x)
		if perp.dot(sep) < 0.0:
			perp = -perp
		ped["state"] = FLEE; ped["flee_dir"] = perp
		ped["flee_t"] = _rng.randf_range(FLEE_TIME.x, FLEE_TIME.y)
		ped["zig_t"] = _rng.randf_range(0.0, TAU)

## Bolt perpendicular to the threat's travel, on the side the ped is already
## on (seeded coin flip when dead-centre in the path).
func _start_flee(ped: Dictionary, body: RigidBody3D, t: Node3D) -> void:
	var tv := _actor_velocity(t); tv.y = 0.0
	var td := tv.normalized() if tv.length() > 0.1 else Vector3.FORWARD
	var perp := Vector3(-td.z, 0.0, td.x)
	var sep := body.global_position - t.global_position; sep.y = 0.0
	if absf(perp.dot(sep)) < 0.2:
		if _rng.randf() < 0.5: perp = -perp  # dead ahead: pick a side
	elif perp.dot(sep) < 0.0:
		perp = -perp
	ped["state"] = FLEE; ped["flee_dir"] = perp
	ped["flee_t"] = _rng.randf_range(FLEE_TIME.x, FLEE_TIME.y)
	ped["zig_t"] = _rng.randf_range(0.0, TAU)  # phase offset: no synced panic

func _update_flee(ped: Dictionary, body: RigidBody3D, delta: float) -> void:
	ped["flee_t"] = float(ped["flee_t"]) - delta
	if float(ped["flee_t"]) <= 0.0:  # panic over: rejoin the loop where nearest
		ped["state"] = WALK
		ped["s"] = _nearest_at(ped, body.global_position)
		ped["fdir"] = 0.0
		return
	ped["zig_t"] = float(ped["zig_t"]) + delta * ZIG_RATE
	var heading := (ped["flee_dir"] as Vector3).rotated(
		Vector3.UP, sin(float(ped["zig_t"])) * ZIG_AMP)  # panicked zigzag
	var zi := _zone_of(ped)
	var pos: Vector3
	if zi >= 0:
		pos = _zone_flee(_zones[zi], ped, body.global_position, heading, FLEE_SPEED * delta)
		var moved := pos - body.global_position
		if moved.length_squared() > 0.0004: heading = moved  # face where he actually went
	else:
		pos = body.global_position + heading * FLEE_SPEED * delta
		var c := ped["center"] as Vector2
		pos.x = clampf(pos.x, c.x - BLOCK_CLAMP, c.x + BLOCK_CLAMP)  # stay on slab
		pos.z = clampf(pos.z, c.y - BLOCK_CLAMP, c.y + BLOCK_CLAMP)
		pos.y = SLAB_TOP + PED_HALF
	_place(body, heading, pos)

## Handoff to loose physics: comedic, bloodless, mannequin tumble. The player
## pays heat + Respect ONCE per ped, and only for a genuinely moving strike.
func _knockdown(ped: Dictionary, body: RigidBody3D, striker: Node) -> void:
	if int(ped["state"]) == DOWN or float(ped["age"]) < GRACE: return
	ped["state"] = DOWN; ped["still_t"] = 0.0
	body.freeze = false
	var sv := Vector3.ZERO
	if striker is Node3D: sv = _actor_velocity(striker as Node3D)
	body.linear_velocity = sv * HIT_CARRY + Vector3.UP * HIT_POP
	body.angular_velocity = Vector3(_rng.randf_range(-4.0, 4.0),
		_rng.randf_range(-2.0, 2.0), _rng.randf_range(-4.0, 4.0))
	var pv := _player()
	if bool(ped["charged"]) or pv == null or striker != pv: return
	if sv.length() < CHARGE_MIN_SPEED: return  # ped walked into a parked car
	ped["charged"] = true  # once per ped, ever
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"): pol.call("add_heat", HEAT_ON_HIT, "HIT A PEDESTRIAN")
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_respect"):
		repo.call("add_respect", RESPECT_ON_HIT, "")

## Public API for combat: force a ped into its DOWN tumble regardless of the
## striker's closing speed (bullets have none). _knockdown's own guards (already
## down, spawn grace) still apply, and its charge branch stays silent for a
## stationary shooter — combat's own once-per-ped meta is the only charge.
func force_knockdown(body: RigidBody3D, striker: Node) -> void:
	var ped := _find(body)
	if ped.is_empty() or int(ped["state"]) == DOWN: return
	_knockdown(ped, body, striker)

## Contact backup for hits the proximity check missed. Static world is NOT a
## hit (speculative slab contacts), and neither is a frozen kinematic peer.
## A strolling character shoves past — only a sprint-speed one bowls peds over.
func _on_contact(other: Node, body: RigidBody3D) -> void:
	if other is StaticBody3D: return
	if other is RigidBody3D and (other as RigidBody3D).freeze: return
	if other is CharacterBody3D \
			and _actor_velocity(other as Node3D).length() < KNOCK_CLOSING: return
	var ped := _find(body)
	if ped.is_empty() or int(ped["state"]) == DOWN: return
	_knockdown(ped, body, other)

## Dust-yourself-off comedy: nearly still for 8 s -> re-freeze standing at the
## nearest sidewalk point and stroll on. Never settles? Distance despawns it.
func _update_down(ped: Dictionary, body: RigidBody3D, delta: float) -> void:
	if body.linear_velocity.length() < STILL_SPEED:
		ped["still_t"] = float(ped["still_t"]) + delta
	else:
		ped["still_t"] = 0.0
	if float(ped["still_t"]) < GETUP_TIME: return
	body.freeze = true
	body.linear_velocity = Vector3.ZERO; body.angular_velocity = Vector3.ZERO
	ped["state"] = WALK
	ped["s"] = _nearest_at(ped, body.global_position)
	_point_at(ped, float(ped["s"]))
	_place(body, _pp_head * float(ped["wdir"]), _pp_pos)

# ============================== PATH GEOMETRY ================================
## Point + heading at path coord s on a block's rounded-square loop (corners
## turned smoothly along quarter arcs). Outputs land in _pp_pos / _pp_head —
## out-params instead of a returned array keep this allocation-free per frame.
func _path_point(c: Vector2, s: float) -> void:
	var k := mini(int(s / PATH_SEG), 3)
	var r := s - float(k) * PATH_SEG
	var d := DIRS[k]; var p0 := P0S[k]
	var pos2: Vector2; var head2: Vector2
	if r <= PATH_STRAIGHT:
		pos2 = p0 + d * r; head2 = d
	else:
		var t := (r - PATH_STRAIGHT) / CORNER_R  # arc angle swept so far
		var arc_c := p0 + d * PATH_STRAIGHT + Vector2(-d.y, d.x) * CORNER_R
		pos2 = arc_c + (Vector2(d.y, -d.x) * CORNER_R).rotated(t)
		head2 = d.rotated(t)
	_pp_pos = Vector3(c.x + pos2.x, SLAB_TOP + PED_HALF, c.y + pos2.y)
	_pp_head = Vector3(head2.x, 0.0, head2.y)

## Nearest loop coord to a world point (event-time only, never per-frame),
## skipping samples inside the protected corridor so nobody re-stands there.
func _nearest_s(c: Vector2, pos: Vector3) -> float:
	var best := 0.0; var bd := INF
	var step := PATH_PERIM / 48.0
	for i in 48:
		var s := step * float(i)
		_path_point(c, s)
		if CORRIDOR.has_point(Vector2(_pp_pos.x, _pp_pos.z)): continue
		var d := Vector2(pos.x - _pp_pos.x, pos.z - _pp_pos.z).length_squared()
		if d < bd: bd = d; best = s
	return best

## ---- A ZONE'S SIDEWALK IS ITS POLYLINE ----
## Same job as _path_point/_nearest_s, same out-params, for a district zone:
## the ped's loop is the line through its points instead of a block's rounded
## square. Segment counts are single digits, so both are a handful of dots.
func _zone_of(ped: Dictionary) -> int:
	var zi := int(ped.get("zone", -1))
	return zi if zi >= 0 and zi < _zones.size() else -1

## Point + heading at arc coord `s` along a zone's polyline.
func _zone_point(z: Dictionary, s: float) -> void:
	var pts: PackedVector2Array = z["pts"]
	var dirs: PackedVector2Array = z["dirs"]
	var lens: PackedFloat32Array = z["lens"]
	var total := float(z["len"])
	var t := wrapf(s, 0.0, total) if bool(z["loop"]) else clampf(s, 0.0, total)
	var i := 0
	while i < lens.size() - 1 and t > lens[i]:
		t -= lens[i]; i += 1
	var p := pts[i] + dirs[i] * clampf(t, 0.0, lens[i])
	_pp_pos = Vector3(p.x, float(z["y"]) + PED_HALF, p.y)
	_pp_head = Vector3(dirs[i].x, 0.0, dirs[i].y)

## Nearest arc coord to a world point. Also leaves the projected point in
## _zn_pos and its perpendicular distance in _zn_off — the panic clamp wants
## both, and a second pass would be a second loop.
func _zone_nearest(z: Dictionary, pos: Vector3) -> float:
	var pts: PackedVector2Array = z["pts"]
	var dirs: PackedVector2Array = z["dirs"]
	var lens: PackedFloat32Array = z["lens"]
	var q := Vector2(pos.x, pos.z)
	var best := 0.0; var bd := INF; var base := 0.0
	_zn_pos = q
	for i in lens.size():
		var t := clampf((q - pts[i]).dot(dirs[i]), 0.0, lens[i])
		var foot := pts[i] + dirs[i] * t
		var d := foot.distance_squared_to(q)
		if d < bd:
			bd = d; best = base + t; _zn_pos = foot
		base += lens[i]
	_zn_off = sqrt(bd)
	return best

## Keep a fleeing zone ped on his own pavement: outside the band, he is pulled
## back to its edge. The downtown equivalent is the BLOCK_CLAMP square.
func _zone_clamp(z: Dictionary, pos: Vector3) -> Vector3:
	_zone_nearest(z, pos)
	var band := float(z["width"])
	var out := pos
	if _zn_off > band:
		var off := Vector2(pos.x, pos.z) - _zn_pos
		var edge := _zn_pos + off * (band / maxf(_zn_off, 0.001))
		out.x = edge.x; out.z = edge.y
	out.y = float(z["y"]) + PED_HALF
	return out

## A district ped panics ALONG his pavement. A sidewalk is two metres wide, so
## the half of the bolt that would cross it becomes speed up the block instead:
## a crowd scattering up the street, not four people running into a storefront
## (and never the moonwalk a hard clamp gives a man shoved at a wall). The side
## he takes is the side the panic pointed, decided ONCE and kept for the run, so
## the zigzag cannot flip him mid-stride.
func _zone_flee(z: Dictionary, ped: Dictionary, from: Vector3, heading: Vector3,
		dist: float) -> Vector3:
	_zone_point(z, _zone_nearest(z, from))
	var tan := _pp_head
	var way := float(ped.get("fdir", 0.0))
	if absf(way) < 0.5:
		way = signf(tan.dot(heading))
		if absf(way) < 0.5: way = float(ped["wdir"])   # shoved dead square: he keeps his face
		ped["fdir"] = way
	var step := tan * way + (heading - tan * tan.dot(heading)) * 0.30
	return _zone_clamp(z, from + step.normalized() * dist)

## Dispatchers: the downtown block loop, or the ped's zone polyline.
func _point_at(ped: Dictionary, s: float) -> void:
	var zi := _zone_of(ped)
	if zi < 0: _path_point(ped["center"] as Vector2, s)
	else: _zone_point(_zones[zi], s)

func _nearest_at(ped: Dictionary, pos: Vector3) -> float:
	var zi := _zone_of(ped)
	if zi < 0: return _nearest_s(ped["center"] as Vector2, pos)
	return _zone_nearest(_zones[zi], pos)

# ============================== PLUMBING =====================================
## Threat-set membership scan, throttled to 0.3 s: the ACTOR (character on foot
## — sprinting through a crowd scatters it — vehicle otherwise), live police
## cruisers, and unfrozen civilian debris. Frozen kinematics are excluded —
## traffic stays on the streets and never reaches the raised sidewalks.
func _refresh_threats(pv: Node3D) -> void:
	_threats.clear()
	if pv != null: _threats.append(pv)
	var pol := _peer("police")
	var hv: Variant = pol.get("heat") if pol != null else null
	_heat = int(hv) if hv is int else 0
	for g: String in ["police", "civilian"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is RigidBody3D and is_instance_valid(n) \
					and not (n as RigidBody3D).freeze and (n as Node).is_inside_tree():
				_threats.append(n)

func _find(body: Node) -> Dictionary:
	for ped in _peds:
		if ped["body"] == body: return ped
	return {}

## The actor peds fear: character when on foot, vehicle otherwise.
func _player() -> Node3D:
	if main_ref == null: return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var v: Variant = main_ref.get("vehicle")
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null

## Duck-typed threat velocity: rigid bodies and characters store it differently.
func _actor_velocity(a: Node3D) -> Vector3:
	if a is RigidBody3D: return (a as RigidBody3D).linear_velocity
	if a is CharacterBody3D: return (a as CharacterBody3D).velocity
	return Vector3.ZERO

## Lazy peer binds (peers may load after us or not exist at all — null-safe).
## Retried on the 0.3 s threat cadence until each appears; never in smoke
## (this system's processing is disabled before the first tick). Gunfire is
## gunfire: the crowd scatters from a cop's muzzle exactly like Book's.
func _bind_combat() -> void:
	if not _combat_bound:
		var combat := _peer("combat")
		if combat != null and combat.has_signal("shot_fired"):
			combat.connect("shot_fired", _on_shot_fired)
			_combat_bound = true
	if not _copfire_bound:
		var copfire := _peer("police_gunfire")
		if copfire != null and copfire.has_signal("shot_fired"):
			copfire.connect("shot_fired", _on_shot_fired)
			_copfire_bound = true
	if not _footcop_bound:
		var footcops := _peer("foot_cops")
		if footcops != null and footcops.has_signal("shot_fired"):
			footcops.connect("shot_fired", _on_shot_fired)
			_footcop_bound = true

## GUNFIRE PANIC: every standing ped within 30 m bolts directly AWAY from the
## muzzle for a long 4 s — the FLEE state reused with an override direction.
func _on_shot_fired(pos: Vector3) -> void:
	for ped in _peds:
		var bv: Variant = ped["body"]   # D-068: validity before the cast, always
		if not is_instance_valid(bv) or not (bv as Node).is_inside_tree(): continue
		var body := bv as RigidBody3D
		if int(ped["state"]) == DOWN: continue  # already floored: stay down
		var away := body.global_position - pos; away.y = 0.0
		if Vector2(away.x, away.z).length() > GUN_PANIC_RADIUS: continue
		var dir: Vector3
		if away.length() > 0.1:
			dir = away.normalized()
		else:  # muzzle directly underfoot: bolt any (seeded) cardinal way
			var d2 := DIRS[_rng.randi_range(0, 3)]
			dir = Vector3(d2.x, 0.0, d2.y)
		ped["state"] = FLEE
		ped["flee_dir"] = dir
		ped["flee_t"] = GUN_PANIC_TIME
		ped["zig_t"] = _rng.randf_range(0.0, TAU)  # phase offset: no synced panic

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null

func _place(body: RigidBody3D, heading: Vector3, pos: Vector3) -> void:
	if heading.length_squared() < 0.0001: heading = Vector3.FORWARD
	body.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), pos)
