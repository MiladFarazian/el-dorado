extends Node
## SIGNAL CYCLE (M18) — THE ONE CLOCK THE CARS AND THE GLASS BOTH READ.
##
## M17 shipped signal-obeying traffic against a STATIC baked lens phase: the
## cars stopped, but nothing ever turned green, so downtown read as a grid of
## forty-two four-way stops (D-021, "known limit"). This file is the missing
## half. It owns the stage schedule, it owns the clock, and it is the single
## source of truth both consumers call:
##
##   traffic.gd  -> _phase() delegates here whenever signal_period > 0
##   city_dressing.gd -> precomputes one lens buffer per SLOT from these same
##                       functions, and this node swaps them on slot change
##
## There is no second copy of the literal to drift. That is deliberate: the
## whole point of M17's pure-function design was that the shells and the glass
## CANNOT disagree, and a duplicated six-stage schedule would have been a much
## worse bet than a duplicated two-state one.
##
## THE CLOCK. `Engine.get_physics_frames()` — not an accumulated delta, not
## wall time. Every node in the same physics tick reads the identical integer,
## so traffic's shells and the dressing's lenses are exactly in step with zero
## shared state, zero start-order sensitivity and zero float drift over a long
## session. It is also deterministic, which keeps the smoke baseline honest.
##
## THE CYCLE (per intersection, one full cycle = 2 x HALF = 40 s):
##   0  NS GREEN   15 s     3  EW GREEN   15 s
##   1  NS AMBER    3 s     4  EW AMBER    3 s
##   2  ALL RED     2 s     5  ALL RED     2 s
## Greens sit in the requested 12-20 s band. The 2 s all-red is not decoration:
## a shell that commits to a late amber crosses the bar at up to 13 m/s and
## needs 13.6 m (bar to box centre) + 13.6 m (centre to far edge) + 2.2 m (half
## a shell) = 29.4 m, i.e. ~2.3 s, to be fully out of the box. Two seconds of
## all-red plus the cross direction's own standing start (a shell released at
## its own bar needs sqrt(2*13.6/5) = 2.3 s just to REACH the centre) means the
## box is always empty before anybody arrives in it.
##
## THE OFFSET is a GREEN WAVE (defect D-010) — see the next block.
##
## PER-FRAME COST: one division, one floor, one fposmod, one int compare. The
## expensive work (swapping five precomputed MultiMesh buffers, 1176 lens
## instances) happens only on a slot boundary — once a second, and only five
## PackedFloat32Array assignments when it does.
## VISUAL-ONLY on this side: no collision, no RNG, no allocation per frame.

# Phase codes. These MUST equal traffic.gd's `enum { PH_GO, PH_CAUTION, PH_STOP }`
# — traffic hands the return value straight back into _signal_limit.
const GO := 0
const CAUTION := 1
const STOP := 2

const AMBER := 3.0                   # yellow interval (s)
const CLEAR := 2.0                   # all-red clearance interval (s)
const HALF := 20.0                   # green + amber + clearance = traffic's
                                     # signal_period (one direction's turn)
const MIN_GREEN := 1.0               # floor if somebody sets a silly half-cycle
const STAGES := 6                    # global stages per full cycle
const PEER_POLL := 1.0               # peer discovery cadence before binding (s)

# ============================== THE GREEN WAVE ===============================
## D-010. M18 shipped `(xi + zi) % 2`: adjacent corners exactly half a cycle
## apart. That is an ANTI-STROBE — it stops the grid flashing in unison — and
## it is NOT coordination. A northbound driver leaving one intersection on
## green reaches the next 7 s later and finds its schedule 20 s out of step,
## i.e. red, at roughly every other block. Driven at the design speed from the
## south edge, the old field caught 2 greens in a row; this one catches 6 of 6.
##
## A green wave is a PROGRESSION offset: each intersection's whole schedule
## runs one block's travel time behind its upstream neighbour, so the green
## opens in front of the platoon instead of behind it. Travel time is the block
## pitch over the design speed — 86 m / 12.3 m/s = 7 s, i.e. 27.5 mph, which is
## a normal downtown progression speed and sits inside traffic.gd's own 9-13
## m/s band, so the ambient shells ride the wave too.
##
## THE FIELD IS DIAGONAL, and that costs nothing: the offset is one term in xi
## plus one term in zi, and a term in xi is CONSTANT along an avenue, so it
## cannot disturb the north-south wave at all. Northbound (zi decreasing — the
## direction the player spawns facing, straight up N 1ST AVE) and eastbound (xi
## increasing) both progress. The two reverse directions pay the classic price
## of one-way progression: the phase runs 2 x 7 s per block against them, so
## they catch two and stop. That is what a real coordinated grid does; you buy
## the peak direction with the off-peak one.
##
##   offset(xi, zi) = PROGRESSION * (xi + (NZ - 1 - zi))     seconds behind
##
## WHY THE PRECOMPUTED BAKE STILL WORKS. city_dressing bakes one MultiMesh
## buffer per index and swaps on change, which requires every intersection's
## local stage to be a function of ONE shared integer. A stage shift cannot
## express 7 s — the six stages are 15/3/2/15/3/2 s, unequal — so the index is
## now a 1-SECOND SLOT of the 40 s cycle instead of a stage. That is EXACT, not
## an approximation: every stage boundary (0/15/18/20/35/38 s) and every offset
## (a multiple of 7 s) is a whole number of seconds, so no intersection can
## change stage in the middle of a slot. The cars read the continuous function
## `local_stage_at(now(), ...)` and the glass reads `slot(now())`, and those are
## provably the same stage at every instant. Cost: 40 slots x 1176 instances of
## baked buffer (2.3 MB) instead of 6, and still zero per-frame work.
const BLOCK_PITCH := 86.0            # downtown grid pitch (greybox BLOCK+STREET)
const PROGRESSION := 7.0             # seconds of offset per block travelled
const DESIGN_SPEED := BLOCK_PITCH / PROGRESSION   # 12.29 m/s = 27.5 mph
const NZ := 6                        # EW streets; zi 0 is the NORTHMOST (z=133)
const SLOT := 1.0                    # bake quantum (s) — see the proof above
const SLOTS := 40                    # int(2 * HALF / SLOT): the whole cycle

var main_ref: Node = null
var _dress: Node = null
var _traffic: Node = null
var _groups: Array = []              # [{mm: MultiMesh, stages: [PackedFloat32Array]}]
var _slot := -1
var _poll := 0.0
var _active := false


# ============================== THE PURE SCHEDULE ============================
## Seconds since boot, from the physics tick counter every node shares.
static func now() -> float:
	return float(Engine.get_physics_frames()) \
		/ float(maxi(Engine.physics_ticks_per_second, 1))


static func green_len(half: float) -> float:
	return maxf(half - AMBER - CLEAR, MIN_GREEN)


## Global stage 0..5 at time `t`. 0-2 serve north-south, 3-5 serve east-west.
static func stage(t: float, half: float) -> int:
	var g := green_len(half)
	var u := fposmod(t, half * 2.0)
	var base := 0
	if u >= half:
		base = 3
		u -= half
	if u < g:
		return base
	if u < g + AMBER:
		return base + 1
	return base + 2


## Seconds this intersection's schedule runs BEHIND the master clock. Whole
## seconds by construction — the slot bake depends on it (see the block above).
static func offset(xi: int, zi: int) -> float:
	return PROGRESSION * float(xi + (NZ - 1 - zi))


## The stage THIS intersection is in at master time `t`. The continuous form:
## traffic.gd's shells read this every physics frame.
static func local_stage_at(t: float, xi: int, zi: int, half: float) -> int:
	return stage(t - offset(xi, zi), half)


## Which precomputed bake slot the whole city is reading right now. One integer
## for 1176 lenses; the per-intersection offsets are already inside the bake.
static func slot(t: float) -> int:
	return int(fposmod(floorf(t / SLOT), float(SLOTS)))


## The stage intersection (xi, zi) holds throughout bake slot `s`. Sampled at
## the slot MIDPOINT: the stage is constant across the slot, so the midpoint is
## the whole interval and no boundary case can go either way.
static func stage_in_slot(s: int, xi: int, zi: int, half: float) -> int:
	return local_stage_at((float(s) + 0.5) * SLOT, xi, zi, half)


static func ns_from_local(l: int) -> int:
	return GO if l == 0 else (CAUTION if l == 1 else STOP)


static func ew_from_local(l: int) -> int:
	return GO if l == 3 else (CAUTION if l == 4 else STOP)


## WHAT traffic.gd's _phase() RETURNS while signal_period > 0. Pure: no node,
## no state, no ordering — callable from a build pass or a physics frame alike.
static func phase(is_ns: bool, xi: int, zi: int, half: float) -> int:
	var l := local_stage_at(now(), xi, zi, half)
	return ns_from_local(l) if is_ns else ew_from_local(l)


## Pedestrian heads run the parallel movement's GREEN and nothing else: WALK
## comes up with the green beside it and drops at the amber, so the amber plus
## both all-reds are the pedestrian clearance interval. That is stricter than
## "walk whenever the traffic you cross is stopped" — correctly so, since the
## crossing you started must also empty before the cross street is released.
static func ped_walk(walks_with_ns: bool, xi: int, zi: int, half: float) -> bool:
	var l := local_stage_at(now(), xi, zi, half)
	return l == (0 if walks_with_ns else 3)


# ============================== RUNTIME ======================================
func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)   # smoke gate: the diorama stays frozen
		return


## Bound to PHYSICS, not process: the slot index is derived from the physics
## frame counter, so swapping here lands the glass in the SAME tick the shells
## first read the new phase. Systems load alphabetically, so this node sits
## before `traffic` in the tree and its _physics_process runs first.
func _physics_process(delta: float) -> void:
	if not _active:
		_poll -= delta
		if _poll > 0.0:
			return
		_poll = PEER_POLL
		_bind()
		if not _active:
			return
	var s := slot(now())
	if s == _slot:
		return
	_slot = s
	for g: Variant in _groups:
		var e := g as Dictionary
		(e["mm"] as MultiMesh).buffer = (e["stages"] as Array)[s]


## Takes ownership of BOTH sides at once, or of neither. Until this succeeds
## the shells run the M17 static phase (signal_period 0) against the M17 static
## glass — delete this file and the game reverts to that diorama exactly.
func _bind() -> void:
	if _dress == null or not is_instance_valid(_dress):
		_dress = _find_dressing()
	if _dress == null:
		return
	if _traffic == null or not is_instance_valid(_traffic):
		_traffic = _peer("traffic")
	if _traffic == null:
		return
	if not _dress.has_method("get_signal_cycle_groups") \
			or not _dress.has_method("set_signal_cycle_active"):
		return
	var got: Variant = _dress.call("get_signal_cycle_groups")
	if not (got is Array) or (got as Array).is_empty():
		return
	_groups = got as Array
	_dress.call("set_signal_cycle_active", true)
	_traffic.set("signal_period", HALF)   # THE SEAM: cars swap with the glass
	_active = true


func _find_dressing() -> Node:
	if main_ref == null:
		return null
	var city: Variant = main_ref.get("city")
	if not (city is Node3D) or not is_instance_valid(city):
		return null
	return (city as Node3D).get_node_or_null("CityDressing")


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n as Node
	return null
