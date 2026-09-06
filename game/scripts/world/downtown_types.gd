extends Node3D
## DOWNTOWN ARCHITECTURAL VOCABULARY (M21) — defect D-023, "downtown is still
## one building repeated."
##
## THE DEFECT. `greybox_city._tower_visual()` is one recipe: a glass shaft, an
## optional inset setback, a concrete cap, sometimes a mast or a tank, sometimes
## a podium. Tint slides north-cool to south-warm and heights fall off from the
## centre, but 108 towers share one window logic, one material and one outline.
## QA measured it: "≈15 towers in frame, every one a rectangular prism in the
## same dark brown with the same beige window grid."
##
## THE FIX, and why it is shaped like this. The `rng`/`drng` draw order in
## `_build_downtown` / `_tower_visual` is a FROZEN contract (the smoke baseline
## is byte-identical through nine milestones), so not one draw moves. Instead
## this is a re-skin pass appended at the very END of `_ready()`, in the D-018
## district-layer tradition: it reads what the build RECORDED
## (`get_tower_segments()`, `get_podium_xforms()`), frees the four tower
## MultiMeshes and the 37 water-tank drums that the recipe emitted, and rebuilds
## every tower from a SEVEN-TYPE vocabulary on its own literal seed.
##
## PHYSICS IS UNTOUCHED. Every tower's collider is the original full box
## `(sx, h, sz)` from M1 — this pass adds ZERO collision and removes none, so
## the smoke corridor x∈[174,212] ∧ z∈[424,576] and the whole layout are
## byte-identical by construction. The rule that keeps the re-skin honest:
## **every type fills the same footprint at grade and puts solid mass at the
## tower's centreline all the way to the recorded top** — so the collider still
## matches what you can see at driving height, plaza_dressing's planter rings
## still hug a wall, and city_dressing's rooftop signs (placed at the tower
## centre, top + 2.6 m) still stand on a roof. Crowns, cornices, cranes and
## billboards project ABOVE the collider, which is exactly what `_roof_cap` and
## `_antenna` already did.
##
## THE SEVEN TYPES — each a different silhouette at 800 m AND a different face
## at 2 m, which is the pair D-023 says is missing:
##   CORP   black-glass curtain box, expressed corner fins, lit crown collar
##   DECO   stepped limestone ziggurat, corner buttresses, lantern + spire
##   MIDSLAB mid-century ribbon slab, solid end walls, projecting flat lid
##   BRICK  pre-war masonry, punched windows, corbelled cornice, fire escape,
##          water tank on a stand
##   DECK   open parking structure — you see daylight between its floor plates
##   SIGNBLOCK low painted block under a rooftop billboard on steel legs
##   SITE   a half-built frame with a tower crane
##
## Five buildings carry names that already exist in the naming bible §6 — the
## Magnate Building (and the Neon Mustang on its roof), Prism Court, the
## Texchange, Needlman & Marks, and the Convention Crater. Nothing here invents
## canon; the remaining 103 towers carry generic signage or none.
##
## BUDGET (measured, not asserted — quality bar §4b): 5 287 instances in 17
## MultiMeshes + 142 Label3D signs, zero per-frame work. Cost over the old
## recipe, A/B on the same machine back to back: +0.45 ms at `street_north`,
## +0.35 ms at `street_detail`. `--perf --perf-only=downtown_day,downtown_night`
## reports 82.5 / 108.0 fps, both inside the 16.67 ms budget.

const TEX := preload("res://scripts/world/city_textures.gd")
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

const SEED := 9310771               # M21 downtown vocabulary ONLY — never `rng`
const BASE_Y := 0.1                 # every recorded tower footprint bottom
const PITCH := 86.0
const ORIGIN := Vector2(150.0, 90.0)          # block (0,0) centre
const CORE := Vector2(451.0, 305.0)           # the Trust's block — downtown's eye
const NS_X: Array[float] = [193.0, 279.0, 365.0, 451.0, 537.0, 623.0, 709.0]
const CORRIDOR_X := Vector2(174.0, 212.0)
const CORRIDOR_Z := Vector2(424.0, 576.0)
const DECK_LEVEL := 3.15            # parking-deck floor-to-floor
const SITE_CAP := 4                 # construction sites are events, not texture

enum Kind {CORP, DECO, MIDSLAB, BRICK, DECK, SIGNBLOCK, SITE}

## ============================ LIT FIXTURES ==================================
## THE DEFECT THIS SOLVES. `main.gd` sets `glow_hdr_threshold = 1.05`, so any
## emissive whose brightest channel clears 1.05 blooms. Round two shipped these
## five sets on ONE energy each, tuned for night: the cool crown collar at 1.7 x
## (0.62, 0.78, 0.95) peaks at **1.62**, and the deck tube at 1.35 x (0.72,
## 0.80, 0.76) peaks at **1.08**. In daylight that is not a light, it is a
## blown white band with a bloom halo wrapped round every tower crown and a
## white slash at every parking level — visible at `aerial`, `trust_tower`,
## `skyline_from_freeway` and `dt_signblock`, and the thing that makes downtown
## look broken at noon.
##
## An emissive cannot be right at both times of day on one number, so it gets
## two, exactly as `suburb_dressing.set_night_level()` already does for the
## porch fixtures. DAY peaks sit under the bloom threshold (the neon sign is
## the one deliberate exception — a landmark sign is allowed to glow at noon).
##
## NIGHT is deliberately set HIGHER than the single value it replaces, and the
## honest measurement is that this comes out NEUTRAL, not better: one tree, two
## arms, D-079's own metric (ground half, bright px > 64/255) reads
## street_night 38 103 -> 37 925, skyline_night 23 262 -> 22 112,
## freeway_night 27 277 -> 26 937. The extra energy is spent paying back the
## emissive AREA the deck tube gave up (0.86 -> 0.58 of the bay), so the ramp
## buys the daylight fix for free after dark — it does NOT close D-079, and
## nobody should read it as closing D-079.
## Cost: one float compare per frame, no allocation.
const LIT_COOL := Color(0.62, 0.78, 0.95)
const LIT_WARM := Color(0.98, 0.80, 0.44)
const LIT_TUBE := Color(0.72, 0.80, 0.76)
const LIT_RED := Color(0.95, 0.20, 0.16)
const LIT_NEON := Color(0.98, 0.32, 0.42)
#                                    cool  warm  tube   red  neon
const DAY_E: Array[float] = [0.10, 0.10, 0.10, 1.05, 1.15]  # D-104: windows were 0.45-0.55 at noon — a glow, not a window; signage stays on
const NIGHT_E: Array[float] = [2.10, 1.90, 2.40, 2.20, 3.60]
const GLOW := preload("res://scripts/systems/streetlight_glow.gd")

## Rooftop billboard copy — canon brands only (§7 companies, §8 institutions,
## §10 apps). A brand that buys I-3 also buys the skyline, so this shares the
## freeway rotation's register, but downtown gets the six advertisers that only
## make sense on a tower: the listing app, the phone assistant, the tithing
## app, the doorbell network, the private-equity landlord and the compute
## ranch. Eighteen boards, so no two towers in one sightline say the same thing.
const ROOF_ADS: Array = [
	["DR. ZING", "24 FLAVORS. ONE IS CLASSIFIED.", Color(0.42, 0.08, 0.12), Color(0.98, 0.92, 0.8)],
	["PARLAYPAL", "A FORECAST YOU CAN BUY\u2122", Color(0.05, 0.42, 0.26), Color(0.95, 0.98, 0.95)],
	["THE TEXAS SLEDGEHAMMER", "1-800-WRECKED \u00b7 SE HABLA JUSTICE", Color(0.08, 0.12, 0.3), Color(1.0, 0.83, 0.25)],
	["LASSOED\u2122", "SOMEBODY IS SETTLING FOR YOU", Color(0.62, 0.12, 0.35), Color(1.0, 0.94, 0.9)],
	["OMNIMIND", "AGI IN 18 MONTHS", Color(0.92, 0.92, 0.92), Color(0.1, 0.1, 0.1)],
	["BLUR+", "THE PRICE WENT UP. YOU DIDN'T CANCEL.", Color(0.28, 0.14, 0.42), Color(0.92, 0.86, 1.0)],
	["SHINDIG BOCK", "SIX GENERATIONS. THREE OWNERS.", Color(0.36, 0.22, 0.10), Color(1.0, 0.9, 0.7)],
	["T-GRID", "THE GRID IS FINE.", Color(0.30, 0.30, 0.32), Color(1.0, 0.72, 0.2)],
	["MAY BELLE COSMETICS", "ASK ME ABOUT MY DOWNLINE", Color(0.72, 0.55, 0.66), Color(0.35, 0.12, 0.28)],
	["11SEVEN", "OPEN ALL NIGHT. LIT LIKE AN INTERROGATION.", Color(0.90, 0.50, 0.10), Color(0.12, 0.28, 0.18)],
	["WOOLY COOLERS", "COLD FOR 11 GENERATIONS", Color(0.70, 0.64, 0.50), Color(0.15, 0.2, 0.35)],
	["WILD WANDA'S", "EIGHT SECONDS. EVERY NIGHT.", Color(0.55, 0.10, 0.12), Color(1.0, 0.88, 0.55)],
	["HOUSEGOBLIN", "YOUR HOME IS WORTH LESS SINCE YOU CLICKED", Color(0.10, 0.34, 0.40), Color(0.85, 0.98, 0.92)],
	["SKYE BY OMNIMIND", "IT LISTENS. IT LEARNS. IT TESTIFIES.", Color(0.16, 0.18, 0.24), Color(0.72, 0.88, 1.0)],
	["SEEDFAITH", "THE BOOK OF NUMBERS \u00b7 LEADERBOARD LIVE", Color(0.86, 0.78, 0.52), Color(0.30, 0.20, 0.08)],
	["PORCHLIGHT", "SOMEBODY IS WALKING. WE'RE ON IT.", Color(0.20, 0.24, 0.34), Color(1.0, 0.86, 0.42)],
	["BOLO CAPITAL", "WE OWN THAT TOO", Color(0.12, 0.13, 0.15), Color(1.0, 0.75, 0.2)],
	["GIGASTEAD", "WE PAY PROPERTY TAX. EVENTUALLY.", Color(0.10, 0.14, 0.12), Color(0.4, 0.9, 0.55)],
]
## GHOST SIGNS — the faded hand-painted wall ads on the party walls. These are
## DEAD businesses and dead prices, which is the whole point of a ghost sign:
## it advertises a city that isn't there any more. The old pass painted the
## same 2026 brands used on the rooftop boards, so downtown's oldest surface
## was selling streaming subscriptions in 1930s lettering. Canon brands appear
## here ONLY at prices that date them (naming bible \u00a77); everything else is a
## pure trade genericism, which is what these walls actually said.
const GHOST_SIGNS: Array[String] = [
	"DRINK\nDR. ZING\n5\u00a2",
	"HOLLERBURGER\n15\u00a2 HAMBURGERS",
	"SOLE STAR\nON ICE",
	"SHINDIG BOCK\nON DRAUGHT",
	"FEED \u00b7 SEED\nCOAL & ICE",
	"WAGON YARD\nHARNESS \u00b7 REPAIRS",
	"COTTON FACTORS\n& GRAIN",
	"ROOMS 75\u00a2\nTRANSIENT & PERMANENT",
	"DRY GOODS\nNOTIONS \u00b7 MILLINERY",
	"ICE \u00b7 COLD STORAGE\nPOULTRY & EGGS",
	"SADDLERY\nBOOTS MADE TO ORDER",
	"UNDERTAKING\n& LIVERY",
]
## Construction hoarding, the boom's own voice. One line per site; picked by
## the tower's grid cell so this adds ZERO draws to the seeded stream.
const HOARDING_SUBS: Array[String] = [
	"A BOLO CAPITAL NEIGHBORHOOD\u2122",
	"263 UNITS \u00b7 9 PARKING SPACES",
	"PRESERVING THE CHARACTER OF WHATEVER WAS HERE",
	"NOW LEASING \u00b7 SEE THE FENCE",
]
## Tenant plates over a corporate lobby — canon §7/§8 institutions.
const LOBBY_TENANTS: Array[String] = [
	"BOLO CAPITAL", "CLINGTEL", "TEXOTRONICS", "OMNIMIND", "GIGASTEAD",
	"T-GRID", "THE DROVER GROUP", "PIONEER VISION", "AMERIGLIDE", "HOWDY AIR",
	"PARLAYPAL", "LONGHORN DYNAMICS", "BLUR+", "OVERFLOW FELLOWSHIP",
]


class Tower extends RefCounted:
	var x := 0.0
	var z := 0.0
	var sx := 0.0
	var sz := 0.0
	var h := 0.0
	var col := 0                     # grid column 0..7
	var row := 0                     # grid row 0..5 (0 = north)
	var podium := false
	var signed := false              # carries a city_dressing rooftop sign
	var kind := 0
	var tag := ""                    # canon §6 name, or "" for the anonymous


# --- element buckets: one MultiMesh each, flushed at the end ------------------
var _corp: Array[Transform3D] = []
var _corp_c: Array[Color] = []
var _deco: Array[Transform3D] = []
var _deco_c: Array[Color] = []
var _ribbon: Array[Transform3D] = []
var _ribbon_c: Array[Color] = []
var _masonry: Array[Transform3D] = []
var _masonry_c: Array[Color] = []
var _block: Array[Transform3D] = []
var _block_c: Array[Color] = []
var _conc: Array[Transform3D] = []
var _conc_c: Array[Color] = []
# Structural concrete that does NOT cast: deck plates/piers/ramps, site frames,
# window sills. See the shadow note in _flush() — these are 70 % of the pass's
# instances and none of them throws a shadow a player could name.
var _shell: Array[Transform3D] = []
var _shell_c: Array[Color] = []
var _steel: Array[Transform3D] = []
var _steel_c: Array[Color] = []
var _panel: Array[Transform3D] = []
var _panel_c: Array[Color] = []
var _cars: Array[Transform3D] = []
var _cars_c: Array[Color] = []
var _tanks: Array[Transform3D] = []
var _lit_cool: Array[Transform3D] = []
var _lit_warm: Array[Transform3D] = []
var _lit_tube: Array[Transform3D] = []
var _lit_red: Array[Transform3D] = []
var _neon: Array[Transform3D] = []
var _net: Array[Transform3D] = []

# The five lit materials, kept so the dusk ramp can retune them (see LIT_*).
var _m_cool: StandardMaterial3D = null
var _m_warm: StandardMaterial3D = null
var _m_tube: StandardMaterial3D = null
var _m_red: StandardMaterial3D = null
var _m_neon: StandardMaterial3D = null
var _sky: Node = null
var _lvl := -1.0


func build(city: Node3D) -> void:
	var towers := _collect(city)
	if towers.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_assign(towers, rng)
	_name_landmarks(towers)
	_strip_recipe(city)
	for t in towers:
		match t.kind:
			Kind.CORP: _build_corp(t, rng)
			Kind.DECO: _build_deco(t, rng)
			Kind.MIDSLAB: _build_midslab(t, rng)
			Kind.BRICK: _build_brick(t, rng)
			Kind.DECK: _build_deck(t, rng)
			Kind.SIGNBLOCK: _build_signblock(t, rng)
			Kind.SITE: _build_site(t, rng)
	_flush(towers)
	set_process(not OS.get_cmdline_user_args().has("--smoke"))
	set_night_level(0.0)


# ============================ THE DUSK RAMP ==================================
## ONE float compare per frame and, on the frames the level actually moves,
## five `emission_energy_multiplier` writes. No allocation, no iteration over
## instances, nothing that scales with the 5 300 boxes this layer draws — the
## §4b row ("no per-frame work over batched instance sets") is respected by
## construction. `level_for_hour` is `streetlight_glow`'s, so downtown agrees
## with the suburb and the freeway about when night starts.
func _process(_d: float) -> void:
	if _sky == null or not is_instance_valid(_sky):
		_sky = _find_sky()
		if _sky == null:
			return
	var tv: Variant = _sky.get("time_of_day")
	if not (tv is float):
		return
	var lvl := GLOW.level_for_hour(tv as float)
	if absf(lvl - _lvl) > 0.0005:
		set_night_level(lvl)


func set_night_level(level: float) -> void:
	var k := clampf(level, 0.0, 1.0)
	_lvl = k
	if _m_cool != null:
		_m_cool.emission_energy_multiplier = lerpf(DAY_E[0], NIGHT_E[0], k)
	if _m_warm != null:
		_m_warm.emission_energy_multiplier = lerpf(DAY_E[1], NIGHT_E[1], k)
	if _m_tube != null:
		_m_tube.emission_energy_multiplier = lerpf(DAY_E[2], NIGHT_E[2], k)
	if _m_red != null:
		_m_red.emission_energy_multiplier = lerpf(DAY_E[3], NIGHT_E[3], k)
	if _m_neon != null:
		_m_neon.emission_energy_multiplier = lerpf(DAY_E[4], NIGHT_E[4], k)


func _find_sky() -> Node:
	var n: Node = get_parent()
	while n != null:
		var sys: Variant = n.get("systems")
		if sys is Dictionary:
			var s: Variant = (sys as Dictionary).get("sky_weather")
			if s is Node and is_instance_valid(s):
				return s as Node
		n = n.get_parent()
	return null


# ============================ READING THE RECORD =============================
## Rebuild one Tower per recorded glass stack. A tower is identified by the
## (x, z) its segments share; the base segment always bottoms at y = 0.1 (probe-
## verified across all 108), so total height is (top of the last segment) - 0.1.
## First-appearance order is preserved, which makes the type draw deterministic.
func _collect(city: Node3D) -> Array[Tower]:
	var out: Array[Tower] = []
	if not city.has_method("get_tower_segments"):
		return out
	var segs_v: Variant = city.call("get_tower_segments")
	if not (segs_v is Array):
		return out
	var index: Dictionary = {}
	for v: Variant in (segs_v as Array):
		if not (v is Transform3D):
			continue
		var xf: Transform3D = v
		var key := "%.3f|%.3f" % [xf.origin.x, xf.origin.z]
		var size := Vector3(xf.basis.x.x, xf.basis.y.y, xf.basis.z.z)
		var top := xf.origin.y + size.y * 0.5
		if index.has(key):
			var known: Tower = out[int(index[key])]
			known.h = maxf(known.h, top - BASE_Y)
			continue
		var t := Tower.new()
		t.x = xf.origin.x
		t.z = xf.origin.z
		t.sx = size.x
		t.sz = size.z
		t.h = top - BASE_Y
		t.col = clampi(int(round((t.x - ORIGIN.x) / PITCH)), 0, 7)
		t.row = clampi(int(round((t.z - ORIGIN.y) / PITCH)), 0, 5)
		index[key] = out.size()
		out.append(t)
	# Podiums: recorded at the tower's own (x, z), so the key matches exactly.
	if city.has_method("get_podium_xforms"):
		var pods: Variant = city.call("get_podium_xforms")
		if pods is Array:
			for v2: Variant in (pods as Array):
				if not (v2 is Transform3D):
					continue
				var pk := "%.3f|%.3f" % [(v2 as Transform3D).origin.x,
					(v2 as Transform3D).origin.z]
				if index.has(pk):
					out[int(index[pk])].podium = true
	# The six roofs city_dressing has already lettered (it sorts get_tower_tops()
	# by height and takes the first six). Those roofs must stay walkable-flat at
	## the centre, so they are forced to CORP and get an OFF-CENTRE penthouse.
	if city.has_method("get_roof_signs"):
		var tops_v: Variant = city.call("get_roof_signs")
		if tops_v is Array:
			var tops: Array = (tops_v as Array)
			for i in mini(6, tops.size()):
				var tk := "%.3f|%.3f" % [(tops[i] as Vector4).x, (tops[i] as Vector4).y]
				if index.has(tk):
					out[int(index[tk])].signed = true
	return out


# ============================ TYPE ASSIGNMENT ================================
## Height decides the band (a 140 m building is not a parking garage), and the
## band's weights decide the type. Two hard gates keep the city plausible:
## a construction site needs an EMPTY ground floor (no recorded retail podium)
## and there are at most four of them; parking decks stay under 58 m. The
## tallest quarter is corporate and deco, the fringe is masonry, decks,
## billboard blocks and sites — so leaving downtown looks like leaving downtown.
func _assign(towers: Array[Tower], rng: RandomNumberGenerator) -> void:
	var sites := 0
	for t in towers:
		if t.signed:
			t.kind = Kind.CORP
			continue
		var r := rng.randf()
		var k := Kind.BRICK
		if t.h >= 100.0:                     # the corporate core: glass and stone
			k = Kind.DECO if r < 0.42 else Kind.CORP
		elif t.h >= 72.0:
			k = Kind.MIDSLAB if r < 0.34 else (Kind.DECO if r < 0.68 else Kind.CORP)
		elif t.h >= 55.0:
			k = Kind.MIDSLAB if r < 0.32 else (Kind.BRICK if r < 0.68 \
				else (Kind.CORP if r < 0.88 else Kind.DECK))
		elif t.h >= 40.0:                    # the working middle of downtown
			k = Kind.BRICK if r < 0.28 else (Kind.DECK if r < 0.62 \
				else (Kind.MIDSLAB if r < 0.78 else Kind.SIGNBLOCK))
		else:                                # the fringe: low, cheap, advertised
			k = Kind.BRICK if r < 0.26 else (Kind.DECK if r < 0.52 \
				else (Kind.SIGNBLOCK if r < 0.80 else Kind.SITE))
		if k == Kind.SITE and (t.podium or sites >= SITE_CAP or _near_corridor(t)):
			k = Kind.SIGNBLOCK
		if k == Kind.SITE:
			sites += 1
		if k == Kind.DECK and t.h >= 58.0:
			k = Kind.MIDSLAB
		t.kind = k


## The smoke lane. Nothing this pass builds carries collision, so a crane jib
## over the corridor could not touch the baseline — it is kept out anyway,
## because a law only enforced when it is inconvenient is not a law.
func _near_corridor(t: Tower) -> bool:
	return t.x > CORRIDOR_X.x - 40.0 and t.x < CORRIDOR_X.y + 40.0 \
		and t.z > CORRIDOR_Z.x - 40.0 and t.z < CORRIDOR_Z.y + 40.0


## Five canon §6 downtown names get a building. Selection is a rule, not a
## coordinate: the best-suited tower of each type nearest the core, skipping
## anything city_dressing already lettered so two signs never stack.
func _name_landmarks(towers: Array[Tower]) -> void:
	_tag_best(towers, Kind.DECO, 105.0, "THE MAGNATE BUILDING")
	_tag_best(towers, Kind.CORP, 110.0, "PRISM COURT")
	_tag_best(towers, Kind.BRICK, 45.0, "THE TEXCHANGE")
	_tag_best(towers, Kind.SIGNBLOCK, 0.0, "NEEDLMAN & MARKS")
	_tag_best(towers, Kind.SITE, 0.0, "THE CONVENTION CRATER")


func _tag_best(towers: Array[Tower], kind: int, min_h: float, tag: String) -> void:
	var best: Tower = null
	var best_d := 1.0e9
	for t in towers:
		if t.kind != kind or t.signed or t.tag != "" or t.h < min_h:
			continue
		var d := Vector2(t.x - CORE.x, t.z - CORE.y).length()
		if d < best_d:
			best_d = d
			best = t
	if best != null:
		best.tag = tag


# ======================= REMOVING THE OLD RECIPE =============================
## The four tower MultiMeshes and the water-tank drums are pure visuals (their
## colliders were emitted separately, `with_visual = false`), so freeing them
## cannot move a collider or a draw. Identifying the tanks by material is exact:
## `mat_tank` is only ever applied to a direct child of the city node by
## `_water_tank()`; the hospital's two tank-coloured boxes are children of a
## StaticBody3D, not of the city, and the helipad drum carries its own material.
func _strip_recipe(city: Node3D) -> void:
	for n: String in ["TowerVisuals", "TowerTrim", "RoofCaps", "Antennas"]:
		var node: Node = city.get_node_or_null(n)
		if node != null:
			node.free()
	var tank_mat: Variant = city.get("mat_tank")
	if tank_mat == null:
		return
	for c in city.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == tank_mat:
			(c as MeshInstance3D).free()


# ============================== TYPE 1 · CORP ================================
## The black-glass corporate box. Its silhouette trick is subtraction, not
## addition: four expressed corner fins run the full height so the outline has
## a visible edge, the shaft steps back once above 90 m, and a lit collar rings
## the crown two floors down — at night this is the type that reads first.
func _build_corp(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var tint := _warmth(t, Color(0.90, 0.93, 0.98), 0.10)
	var tx := t.sx
	var tz := t.sz
	var h1 := t.h                        # where the shaft steps back (top if never)
	if t.h >= 90.0:
		h1 = t.h * rng.randf_range(0.68, 0.78)
		_add(_corp, _corp_c, Vector3(t.sx, h1, t.sz), Vector3(t.x, BASE_Y + h1 * 0.5, t.z), tint)
		tx = t.sx * 0.80
		tz = t.sz * 0.80
		_add(_corp, _corp_c, Vector3(tx, t.h - h1, tz),
			Vector3(t.x, BASE_Y + h1 + (t.h - h1) * 0.5, t.z), tint)
		_add(_conc, _conc_c, Vector3(t.sx + 1.0, 0.9, t.sz + 1.0),
			Vector3(t.x, BASE_Y + h1 + 0.2, t.z), Color(0.80, 0.80, 0.79))
	else:
		_add(_corp, _corp_c, Vector3(t.sx, t.h, t.sz),
			Vector3(t.x, BASE_Y + t.h * 0.5, t.z), tint)
	# Corner fins: a 0.75 m pier sitting ON each corner, so it stands 0.37 m
	# proud of both faces and the vertical edge catches a highlight.
	#
	# THEY STEP WITH THE SHAFT, and that is the whole point of this block.
	# Round two ran ONE pier per corner at the LOWER footprint corner for the
	# building's full height. Above the setback the upper shaft is 0.80x, so
	# the pier stood in open air — measured at up to 1.98 m of clear gap on all
	# 14 setback towers — and its top (t.sx*0.5 + 0.375) reached past the
	# parapet (0.40*t.sx + 0.45), so it poked into the sky as a loose stick.
	# Photographed looking up an avenue at `dt_fin_up`: four towers, sixteen
	# poles hanging in clear sky. A pier dies into the cornice it meets and a
	# new one starts on the block above; that is what the building does.
	for fx: float in [-1.0, 1.0]:
		for fz: float in [-1.0, 1.0]:
			_add(_steel, _steel_c, Vector3(0.75, h1 - 0.2, 0.75),
				Vector3(t.x + fx * t.sx * 0.5, BASE_Y + 0.2 + (h1 - 0.2) * 0.5,
					t.z + fz * t.sz * 0.5), Color(0.30, 0.31, 0.34))
			var uh := t.h - h1 - 1.25       # stops under the parapet soffit
			if uh > 1.0:
				_add(_steel, _steel_c, Vector3(0.68, uh, 0.68),
					Vector3(t.x + fx * tx * 0.5, BASE_Y + h1 + uh * 0.5,
						t.z + fz * tz * 0.5), Color(0.30, 0.31, 0.34))
	# Crown: parapet, a lit collar, and a second lit band below it.
	_add(_conc, _conc_c, Vector3(tx + 0.9, 1.5, tz + 0.9),
		Vector3(t.x, top - 0.3, t.z), Color(0.26, 0.27, 0.29))
	_lit_cool.append(_xf(Vector3(tx + 1.1, 0.85, tz + 1.1), Vector3(t.x, top - 2.6, t.z)))
	# The second band was `tx * 0.94` — SMALLER than the shaft it was meant to
	# ring, so all 22 instances were sealed inside the glass and lit nothing.
	# Probe: "22 of 22 CORP towers have their lower lit collar INSIDE the shaft".
	_lit_cool.append(_xf(Vector3(tx + 0.45, 0.5, tz + 0.45), Vector3(t.x, top - 6.4, t.z)))
	# Rooftop plant, pushed off the centreline so a rooftop sign can stand there.
	var off := Vector2(tx * 0.24, tz * 0.24)
	_add(_conc, _conc_c, Vector3(tx * 0.40, 4.2, tz * 0.40),
		Vector3(t.x + off.x, top + 2.1, t.z - off.y), Color(0.52, 0.52, 0.50))
	_add(_steel, _steel_c, Vector3(0.34, rng.randf_range(9.0, 17.0), 0.34),
		Vector3(t.x - off.x, top + rng.randf_range(9.0, 17.0) * 0.5, t.z + off.y),
		Color(0.22, 0.22, 0.24))
	if t.tag == "PRISM COURT":
		_prism_crown(t, top, tx, tz, tint)
	if not t.podium:
		_lobby(t, rng)


## Prism Court's crown (naming bible §6): four telescoping glass steps that
## taper the top into a faceted point instead of a flat lid.
func _prism_crown(t: Tower, top: float, tx: float, tz: float, tint: Color) -> void:
	for k in 4:
		var f := 0.86 - 0.20 * float(k)
		_add(_corp, _corp_c, Vector3(tx * f, 3.6, tz * f),
			Vector3(t.x, top + 3.0 + 3.6 * float(k), t.z), tint)
	_lit_cool.append(_xf(Vector3(tx * 0.14, 1.2, tz * 0.14),
		Vector3(t.x, top + 18.0, t.z)))


# ============================== TYPE 2 · DECO ================================
## The 1929 setback tower. Four telescoping steps, a cornice at every setback,
## corner buttresses that stand a metre and a half above each step, and a tiered
## lantern under a spire. Pale limestone against the black-glass boxes: the two
## tall types differ in value, not only in outline.
const DECO_STEPS: Array[float] = [1.00, 0.82, 0.64, 0.46]
const DECO_SHARE: Array[float] = [0.44, 0.24, 0.18, 0.14]


func _build_deco(t: Tower, rng: RandomNumberGenerator) -> void:
	var stone := _warmth(t, Color(0.95, 0.92, 0.86), 0.08)
	var trim := stone * 0.86
	var y := BASE_Y
	for k in 4:
		var f: float = DECO_STEPS[k]
		var sh: float = t.h * DECO_SHARE[k]
		var w := t.sx * f
		var d := t.sz * f
		_add(_deco, _deco_c, Vector3(w, sh, d), Vector3(t.x, y + sh * 0.5, t.z), stone)
		# Corner buttresses, projecting and rising past the setback cornice.
		for bx: float in [-1.0, 1.0]:
			for bz: float in [-1.0, 1.0]:
				_add(_deco, _deco_c, Vector3(1.5, sh + 1.7, 1.5),
					Vector3(t.x + bx * w * 0.5, y + (sh + 1.7) * 0.5, t.z + bz * d * 0.5), trim)
		_add(_conc, _conc_c, Vector3(w + 1.3, 0.85, d + 1.3),
			Vector3(t.x, y + sh + 0.42, t.z), trim)
		y += sh
	# Lantern: three shrinking drums, then the spire.
	var lw := t.sx * 0.34
	var ld := t.sz * 0.34
	for k2 in 3:
		var f2 := 1.0 - 0.26 * float(k2)
		_add(_deco, _deco_c, Vector3(lw * f2, 3.0, ld * f2),
			Vector3(t.x, y + 1.5 + 3.0 * float(k2), t.z), stone)
	_lit_warm.append(_xf(Vector3(lw + 0.6, 0.55, ld + 0.6), Vector3(t.x, y + 0.35, t.z)))
	# The lantern tops out at y + 9; whatever stands above it starts THERE, so it
	# is carried by the building instead of hanging over it (round one floated the
	# Mustang and its derrick in clear air above the spire tip).
	var crown_top := y + 9.0
	if t.tag == "THE MAGNATE BUILDING":
		_neon_mustang(t, crown_top)
		_crown_name(t, BASE_Y + t.h * 0.76, "THE MAGNATE BUILDING", DECO_STEPS[2])
	else:
		var spire := clampf(t.h * 0.11, 6.0, 17.0)
		_add(_steel, _steel_c, Vector3(0.9, spire, 0.9),
			Vector3(t.x, crown_top + spire * 0.5, t.z), Color(0.44, 0.42, 0.38))
		_lit_red.append(_xf(Vector3(0.7, 0.7, 0.7),
			Vector3(t.x, crown_top + spire + 0.4, t.z)))
	if not t.podium:
		_lobby(t, rng)


## THE NEON MUSTANG (naming bible §6: the Pegasus sign, atop the Magnate
## Building). A leaping horse drawn in eleven neon tubes on a rooftop derrick,
## turning with the tower's axis — downtown's second nameable object after the
## Green Light, and the first one you can name by SHAPE rather than colour.
func _neon_mustang(t: Tower, y: float) -> void:
	const S := 2.0                    # 7 m body -> 14 m: a shape, not a pink dot
	var yaw := 0.35
	var rot := Basis(Vector3.UP, yaw)
	# A galloping horse drawn in TILTED bars — round one stacked axis-aligned
	# boxes and the sign read as a blob. Each entry is [size, offset, tilt]; the
	# tilt turns the bar inside the sign's own plane (about the sign normal, so
	# `rot * Basis(BACK, tilt) * from_scale` — never Basis.scaled on a rotation).
	var parts: Array = [
		[Vector3(7.0, 1.7, 0.45), Vector2(0.0, 0.0), 0.08],       # barrel
		[Vector3(2.8, 1.6, 0.45), Vector2(-3.7, -0.3), -0.16],    # rump
		[Vector3(3.4, 1.4, 0.45), Vector2(4.0, 1.7), 0.60],       # neck
		[Vector3(2.3, 1.1, 0.45), Vector2(5.9, 3.2), 0.16],       # head
		[Vector3(2.8, 0.6, 0.45), Vector2(3.4, 2.9), 0.95],       # mane
		[Vector3(3.0, 0.8, 0.45), Vector2(3.7, -1.5), -0.95],     # near foreleg
		[Vector3(2.5, 0.75, 0.45), Vector2(2.1, -2.0), -1.30],    # off foreleg
		[Vector3(3.2, 0.85, 0.45), Vector2(-3.6, -1.7), 2.05],    # near hind
		[Vector3(2.7, 0.8, 0.45), Vector2(-2.3, -2.1), 1.65],     # off hind
		[Vector3(3.2, 0.75, 0.45), Vector2(-5.2, 1.0), 2.55],     # tail
	]
	# WHERE THE HORSE SITS, derived rather than guessed. The lowest neon bar is
	# the off hind: centre 2.1 S below the hub, half-length 1.35 S, tilted 1.65
	# rad, so it reaches 2.1 S + (2.7 S * 0.5 * sin 1.65 + 0.8 S * 0.5 * cos 1.65)
	# = 3.48 S below the hub. Round two put the hub at 4.4 S over the beam top,
	# which left the lowest hoof 1.39 m ABOVE the beam — photographed at
	# `trust_tower` as a horse hovering over an empty steel table. The hub is
	# now placed so that bar lands 0.25 m INSIDE the beam.
	const DROP := 3.48                 # lowest neon bar below the hub, in S
	var beam_top := y + 8.45
	var hub := Vector3(t.x, beam_top - 0.25 + DROP * S, t.z)
	for p: Array in parts:
		var o: Vector2 = p[1]
		_neon.append(Transform3D(
			rot * Basis(Vector3.BACK, p[2] as float) * Basis.from_scale((p[0] as Vector3) * S),
			hub + rot * Vector3(o.x * S, o.y * S, 0.0)))
	# The derrick: four legs and a head beam the horse sits on, so the sign is
	# CARRIED. Round two stood the legs at a fixed +-3.4 / +-1.5 m on the
	# lantern's TOP drum, which is only 0.082 * t.sx half-wide — so the legs
	# landed 1.8 m outside the thing they were standing on and the rig read as
	# a table floating beside the spire. They now bracket the whole lantern and
	# foot on the top setback step (0.23 * t.sx half-wide), which is the only
	# surface up here wide enough to carry them.
	var lx := t.sx * 0.19
	var lz := t.sz * 0.19
	var leg_h := 17.0                  # top setback step -> beam, the lantern is 9 m
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_steel.append(Transform3D(rot * Basis.from_scale(Vector3(0.36, leg_h, 0.36)),
				Vector3(t.x, y - 9.0 + leg_h * 0.5, t.z) + rot * Vector3(dx * lx, 0.0, dz * lz)))
			_steel_c.append(Color(0.26, 0.26, 0.28))
	_steel.append(Transform3D(rot * Basis.from_scale(Vector3(lx * 2.2, 0.5, lz * 2.2)),
		Vector3(t.x, y + 8.2, t.z)))
	_steel_c.append(Color(0.26, 0.26, 0.28))
	# Aviation light on a stub mast at the tail end of the beam, pushed out of
	# the sign plane. Round two hung it at y + 9.4 S — a red cube alone in the
	# sky 3.6 m above the highest neon bar, carried by nothing.
	var mast := rot * Vector3(-lx * 0.9, 0.0, lz * 1.0)
	_steel.append(Transform3D(Basis.from_scale(Vector3(0.22, 2.4, 0.22)),
		Vector3(t.x, beam_top + 1.2, t.z) + mast))
	_steel_c.append(Color(0.26, 0.26, 0.28))
	_lit_red.append(_xf(Vector3(0.6, 0.6, 0.6),
		Vector3(t.x, beam_top + 2.6, t.z) + mast))


# ============================ TYPE 3 · MIDSLAB ===============================
## 1962: a horizontal ribbon of glass over a precast spandrel, repeated all the
## way up, solid end walls, an eyebrow ledge every third floor, and a flat lid
## that oversails the whole building. Everything about it is horizontal, which
## is what makes the deco tower beside it look vertical.
func _build_midslab(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var pale := _warmth(t, Color(0.94, 0.93, 0.90), 0.06)
	_add(_ribbon, _ribbon_c, Vector3(t.sx, t.h, t.sz),
		Vector3(t.x, BASE_Y + t.h * 0.5, t.z), pale)
	# ONE blank precast end wall, and it faces AWAY from the nearest avenue —
	# round one put a party wall on both ±X faces and half of downtown showed
	# the street a blank cream box (caught at `street_north`). The avenue face
	# keeps its ribbon; the alley face gets the gable.
	var away := -signf(_nearest_avenue(t.x) - t.x)
	if away == 0.0:
		away = -1.0
	_add(_conc, _conc_c, Vector3(0.55, t.h, t.sz * 0.99),
		Vector3(t.x + away * t.sx * 0.5, BASE_Y + t.h * 0.5, t.z), pale * 0.93)
	# Exposed precast frame: a pier on each corner, so the ribbon reads as infill
	# between structure rather than as a decal on a box.
	for fx: float in [-1.0, 1.0]:
		for fz: float in [-1.0, 1.0]:
			_add(_conc, _conc_c, Vector3(0.85, t.h, 0.85),
				Vector3(t.x + fx * t.sx * 0.5, BASE_Y + t.h * 0.5, t.z + fz * t.sz * 0.5),
				pale * 0.97)
	# Eyebrow ledges every three floors.
	var y := BASE_Y + 9.6
	while y < top - 4.0:
		_add(_conc, _conc_c, Vector3(t.sx + 0.9, 0.3, t.sz + 0.9),
			Vector3(t.x, y, t.z), pale * 0.90)
		y += 9.6
	# The lid: a thin slab oversailing 0.9 m on every side, then plant.
	_add(_conc, _conc_c, Vector3(t.sx + 1.8, 0.6, t.sz + 1.8),
		Vector3(t.x, top + 0.3, t.z), pale * 0.82)
	_add(_conc, _conc_c, Vector3(t.sx * 0.42, 3.4, t.sz * 0.42),
		Vector3(t.x + t.sx * 0.2, top + 2.3, t.z - t.sz * 0.18), Color(0.55, 0.55, 0.53))
	_add(_conc, _conc_c, Vector3(t.sx * 0.16, 4.6, t.sz * 0.16),
		Vector3(t.x - t.sx * 0.26, top + 2.9, t.z + t.sz * 0.22), Color(0.52, 0.52, 0.50))
	_lit_tube.append(_xf(Vector3(t.sx * 0.7, 0.3, 0.3),
		Vector3(t.x, top + 0.9, t.z + t.sz * 0.5 + 0.9)))
	if not t.podium:
		_lobby(t, rng)


# ============================== TYPE 4 · BRICK ===============================
## Pre-war masonry: a stone plinth, a belt course, punched windows, a corbelled
## two-stage cornice and a parapet above it, a water tank on a stand, and a fire
## escape zig-zagging down the face that looks at the nearest avenue. This is
## the only type whose wall is mostly solid, so it holds the light differently
## from every glass building beside it.
func _build_brick(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var warm := rng.randf()
	var brick := Color(1.0, 0.94, 0.90) if warm < 0.45 else \
		(Color(0.88, 0.78, 0.62) if warm < 0.75 else Color(0.76, 0.70, 0.66))
	brick = _warmth(t, brick, 0.05)
	var stone := Color(0.80, 0.78, 0.72)
	_add(_masonry, _masonry_c, Vector3(t.sx, t.h, t.sz),
		Vector3(t.x, BASE_Y + t.h * 0.5, t.z), brick)
	_add(_conc, _conc_c, Vector3(t.sx + 0.55, 3.4, t.sz + 0.55),
		Vector3(t.x, BASE_Y + 1.7, t.z), stone)
	_add(_conc, _conc_c, Vector3(t.sx + 0.4, 0.5, t.sz + 0.4),
		Vector3(t.x, BASE_Y + t.h * 0.34, t.z), stone * 0.94)
	_add(_conc, _conc_c, Vector3(t.sx + 1.9, 0.9, t.sz + 1.9),
		Vector3(t.x, top - 0.9, t.z), stone)
	_add(_conc, _conc_c, Vector3(t.sx + 1.2, 0.75, t.sz + 1.2),
		Vector3(t.x, top - 1.75, t.z), stone * 0.9)
	_add(_masonry, _masonry_c, Vector3(t.sx + 0.3, 1.6, t.sz + 0.3),
		Vector3(t.x, top + 0.4, t.z), brick * 0.92)
	# Water tank on a four-leg stand, off the centreline.
	var r := clampf(t.sx * 0.20, 1.1, 2.2)
	var tank_x := t.x + t.sx * 0.22
	var tank_z := t.z - t.sz * 0.20
	_tanks.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.7, r)),
		Vector3(tank_x, top + 3.6 + r * 0.85, tank_z)))
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			_add(_steel, _steel_c, Vector3(0.24, 3.4, 0.24),
				Vector3(tank_x + lx * r * 0.62, top + 1.9, tank_z + lz * r * 0.62),
				Color(0.30, 0.26, 0.22))
	_add(_conc, _conc_c, Vector3(1.3, 2.4, 1.3),
		Vector3(t.x - t.sx * 0.26, top + 2.4, t.z + t.sz * 0.24), stone * 0.8)
	# Fire escape on the face that looks at the nearest north-south avenue.
	var street := _nearest_avenue(t.x)
	var sgn := signf(street - t.x)
	if sgn == 0.0:
		sgn = 1.0
	var fx := t.x + sgn * (t.sx * 0.5 + 0.95)
	var y := BASE_Y + 4.6
	while y < top - 3.0:
		_add(_steel, _steel_c, Vector3(1.9, 0.12, 3.0), Vector3(fx, y, t.z),
			Color(0.22, 0.20, 0.19))
		_add(_steel, _steel_c, Vector3(0.09, 1.05, 3.0),
			Vector3(fx + sgn * 0.9, y + 0.55, t.z), Color(0.22, 0.20, 0.19))
		y += 3.2
	for pz: float in [-1.0, 1.0]:
		_add(_steel, _steel_c, Vector3(0.14, t.h - 5.0, 0.14),
			Vector3(fx + sgn * 0.9, BASE_Y + 2.5 + (t.h - 5.0) * 0.5, t.z + pz * 1.45),
			Color(0.22, 0.20, 0.19))
	if t.tag == "THE TEXCHANGE":
		_portico(t, sgn)
	elif not t.podium:
		_lobby(t, rng)


## THE TEXCHANGE (naming bible §6, on Howdy Street): a six-column stone portico
## across the avenue face, an entablature with the name cut into it, and the
## cattle-horn bell over the door. A street-level face no other type has.
func _portico(t: Tower, sgn: float) -> void:
	var stone := Color(0.86, 0.84, 0.78)
	var w := t.sz * 0.9
	var fx := t.x + sgn * (t.sx * 0.5 + 1.9)
	for k in 6:
		var zz := t.z - w * 0.5 + w * (float(k) + 0.5) / 6.0
		_add(_conc, _conc_c, Vector3(1.5, 9.0, 1.5), Vector3(fx, BASE_Y + 4.5, zz), stone)
		_add(_conc, _conc_c, Vector3(1.9, 0.5, 1.9), Vector3(fx, BASE_Y + 0.3, zz), stone)
		_add(_conc, _conc_c, Vector3(1.8, 0.45, 1.8), Vector3(fx, BASE_Y + 9.2, zz), stone)
	_add(_conc, _conc_c, Vector3(4.2, 1.9, w + 1.6),
		Vector3(fx, BASE_Y + 10.4, t.z), stone)
	_add(_conc, _conc_c, Vector3(3.0, 1.3, w * 0.7),
		Vector3(fx, BASE_Y + 11.9, t.z), stone * 0.95)
	# Soffit downlight UNDER the entablature — round one hung it in clear air
	# above the pediment, which read as a glowing cube parked over the roof.
	_lit_warm.append(_xf(Vector3(1.0, 0.22, w * 0.55),
		Vector3(fx, BASE_Y + 9.32, t.z)))
	_label("THE TEXCHANGE", Vector3(fx + sgn * 2.2, BASE_Y + 10.4, t.z),
		atan2(sgn, 0.0), w * 0.94, Color(0.24, 0.22, 0.18), 200,
		SIGN.MARQUEE, 1.20)


# ============================== TYPE 5 · DECK ================================
## An open parking structure. Floor plate, spandrel rail, floor plate, spandrel
## rail — and daylight in the 2.2 m gap between them, all the way through the
## building. A stair-and-lift tower stands five metres above the top deck, a
## helical ramp climbs the north edge, and a strip light under every plate makes
## it the one thing downtown that reads as a striped object after dark.
## The entry mouth and the ramp are a promise: the collider is still solid, so
## this is a garage you cannot drive into YET.
func _build_deck(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var conc := Color(0.90, 0.89, 0.86)
	var levels := maxi(int(t.h / DECK_LEVEL), 4)
	# Eight piers, ON the facade plane rather than inset — round one hid them
	# behind the spandrel overhang and the building read as a stack of shelves
	# with nothing holding it up.
	for cx: float in [-1.0, 0.0, 1.0]:
		for cz: float in [-1.0, 0.0, 1.0]:
			if cx == 0.0 and cz == 0.0:
				continue
			_add(_shell, _shell_c, Vector3(0.95, t.h, 0.95),
				Vector3(t.x + cx * t.sx * 0.5, BASE_Y + t.h * 0.5,
					t.z + cz * t.sz * 0.5), conc * 0.93)
	for k in range(1, levels + 1):
		var y := BASE_Y + DECK_LEVEL * float(k)
		if y > top:
			break
		_add(_shell, _shell_c, Vector3(t.sx, 0.34, t.sz), Vector3(t.x, y, t.z), conc)
		_add(_shell, _shell_c, Vector3(t.sx + 0.22, 0.95, t.sz + 0.22),
			Vector3(t.x, y + 0.85, t.z), conc * 0.97)
		# Fluorescent strip at the ceiling edge of all four faces, just inboard
		# of the spandrel, so the light actually escapes the building. Round one
		# put two strips deep inside and the garage was a black void at night.
		#
		# ROUND THREE, two corrections. (a) The tube hung at y - 0.55, which is
		# 0.38 m BELOW the slab soffit (the plate bottoms at y - 0.17) — a
		# strip light floating in mid-air. It is now flush under the slab.
		# (b) It ran t.sx * 0.86, nearly wall to wall, and a parking deck is
		# see-through by design, so through every near opening you also saw the
		# FAR wall's full-width ribbon: the type read as a stack of white
		# slashes rather than as a garage (`street_detail`, `dt_signblock`).
		# A run over the aisle is shorter, and the piers occlude the far one.
		for sgn: float in [-1.0, 1.0]:
			_lit_tube.append(_xf(Vector3(t.sx * 0.58, 0.12, 0.18),
				Vector3(t.x, y - 0.24, t.z + sgn * (t.sz * 0.5 - 0.35))))
			_lit_tube.append(_xf(Vector3(0.18, 0.12, t.sz * 0.58),
				Vector3(t.x + sgn * (t.sx * 0.5 - 0.35), y - 0.24, t.z)))
		# The express ramp, entirely INSIDE the plan (round one flew it out past
		# the facade as a wedge): a sloped plate seen through the openings.
		if k < levels:
			var run := t.sz * 0.55
			var ang := atan2(DECK_LEVEL, run)
			_shell.append(Transform3D(Basis(Vector3.RIGHT, -ang)
				* Basis.from_scale(Vector3(t.sx * 0.34, 0.26, run / cos(ang))),
				Vector3(t.x + (t.sx * 0.22 if k % 2 == 0 else -t.sx * 0.22),
					y + DECK_LEVEL * 0.5, t.z)))
			_shell_c.append(conc * 0.88)
	# Stair and lift tower at one corner, five metres above the top deck.
	var sx2 := t.x + t.sx * 0.5 - 2.7
	var sz2 := t.z + t.sz * 0.5 - 2.7
	_add(_shell, _shell_c, Vector3(5.0, t.h + 5.5, 5.0),
		Vector3(sx2, BASE_Y + (t.h + 5.5) * 0.5, sz2), conc * 0.86)
	_lit_tube.append(_xf(Vector3(0.5, 3.0, 0.5), Vector3(sx2 - 2.6, BASE_Y + 8.0, sz2)))
	# Top-deck light poles.
	for px: float in [-1.0, 1.0]:
		for pz: float in [-1.0, 1.0]:
			var p := Vector3(t.x + px * (t.sx * 0.5 - 2.0), top,
				t.z + pz * (t.sz * 0.5 - 2.0))
			_add(_steel, _steel_c, Vector3(0.2, 5.0, 0.2), p + Vector3(0, 2.5, 0),
				Color(0.28, 0.29, 0.31))
			_lit_tube.append(_xf(Vector3(1.1, 0.22, 0.5), p + Vector3(0, 5.05, 0)))
	# Parked cars you can see through the openings — the tell that it is a garage.
	var palette: Array[Color] = [Color(0.72, 0.72, 0.74), Color(0.14, 0.15, 0.17),
		Color(0.55, 0.13, 0.12), Color(0.16, 0.27, 0.45), Color(0.75, 0.72, 0.62)]
	# ONE BAY ROW PER LEVEL, NOSE IN. Round two drew each car's x independently
	# inside +-0.32 * t.sx and put two of the four on each z side, so cars
	# routinely occupied the same slot: the coplanarity probe found 30 pairs of
	# parked cars sharing an EXACT top plane and an EXACT z plane inside the
	# decks, and a deck is see-through, so you saw it. Slots are now a rule.
	# Both rng draws per car are kept, in order, so nothing downstream moves.
	for k2 in range(1, mini(levels, 5)):
		var y2 := BASE_Y + DECK_LEVEL * float(k2) + 0.95
		for c in 4:
			var jit := rng.randf_range(-0.35, 0.35)
			var cxp := t.x + t.sx * (float(c) - 1.5) * 0.22 + jit
			# all four on the -Z side: the stair-and-lift core owns the +X/+Z
			# corner and a car parked into it reads as a car inside a wall.
			var czp := t.z - t.sz * 0.26
			_cars.append(Transform3D(Basis(Vector3.UP, PI * 0.5)
				* Basis.from_scale(Vector3(4.4, 1.25, 1.85)), Vector3(cxp, y2, czp)))
			_cars_c.append(palette[rng.randi_range(0, 4)])
	var face := signf(_nearest_avenue(t.x) - t.x)
	if face == 0.0:
		face = 1.0
	_label("PARK", Vector3(sx2 + face * 2.7, BASE_Y + 12.0, sz2),
		atan2(face, 0.0), 3.9, Color(0.95, 0.93, 0.86), 260, SIGN.CHANNEL, 3.0)
	_label("$12 EARLY BIRD · $40 EVENT",
		Vector3(t.x + face * (t.sx * 0.5 + 0.35), BASE_Y + 3.1, t.z),
		atan2(face, 0.0), t.sz * 0.8, Color(0.95, 0.88, 0.4), 90,
		SIGN.STENCIL, 0.80)


# =========================== TYPE 6 · SIGNBLOCK ===============================
## The two-storey painted box that exists to hold up a billboard. Downtown's
## fringe is full of them and they are the reason the skyline has a bottom edge
## made of advertising rather than of architecture.
func _build_signblock(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var paints: Array[Color] = [Color(0.94, 0.92, 0.86), Color(0.80, 0.83, 0.78),
		Color(0.86, 0.80, 0.74), Color(0.74, 0.79, 0.84), Color(0.90, 0.85, 0.72)]
	var paint := _warmth(t, paints[rng.randi_range(0, 4)], 0.05)
	_add(_block, _block_c, Vector3(t.sx, t.h, t.sz),
		Vector3(t.x, BASE_Y + t.h * 0.5, t.z), paint)
	# Punched office windows on the two avenue faces only — the cross faces stay
	# blank party walls, which is WHY this type exists and where the roof sign's
	# ghost lettering would go. Round one glazed nothing and shipped a white box.
	var wy := BASE_Y + 5.4
	while wy < top - 3.0:
		for wsgn: float in [-1.0, 1.0]:
			for k in 3:
				var wz := t.z + t.sz * (float(k) - 1.0) * 0.28
				_add(_panel, _panel_c, Vector3(0.22, 1.7, t.sz * 0.19),
					Vector3(t.x + wsgn * (t.sx * 0.5 + 0.06), wy, wz), Color(0.14, 0.16, 0.19))
				_add(_shell, _shell_c, Vector3(0.42, 0.2, t.sz * 0.24),
					Vector3(t.x + wsgn * (t.sx * 0.5 + 0.06), wy - 0.95, wz), paint * 0.86)
		wy += 3.6
	_add(_conc, _conc_c, Vector3(t.sx + 1.1, 0.6, t.sz + 1.1),
		Vector3(t.x, top - 0.3, t.z), paint * 0.82)
	_add(_block, _block_c, Vector3(t.sx + 0.5, 1.3, t.sz + 0.5),
		Vector3(t.x, top + 0.65, t.z), paint * 0.9)
	# GHOST SIGN on the two blank party walls. A 20 x 30 m unbroken cream face
	# looking straight down an avenue reads as unfinished (caught at
	# `street_north`); a faded hand-painted wall ad is what is actually there,
	# and it gives the type a second satire surface.
	var ghost: String = GHOST_SIGNS[rng.randi_range(0, GHOST_SIGNS.size() - 1)]
	for gz: float in [1.0, -1.0]:
		_label(ghost, Vector3(t.x, BASE_Y + t.h * 0.62,
			t.z + gz * (t.sz * 0.5 + 0.07)), 0.0 if gz > 0.0 else PI,
			t.sx * 0.84, (paint * 0.55).lerp(Color(0.30, 0.22, 0.18), 0.6),
			230, SIGN.GHOST, t.h * 0.30)
	# The billboard, squared onto the nearest avenue.
	var face := signf(_nearest_avenue(t.x) - t.x)
	if face == 0.0:
		face = 1.0
	var yaw := atan2(face, 0.0)
	var rot := Basis(Vector3.UP, yaw)
	var pw := minf(t.sz * 0.95, 14.0)
	var ph := pw * 0.38
	var py := top + 4.2 + ph * 0.5
	for lx: float in [-0.34, 0.34]:
		_steel.append(Transform3D(rot * Basis.from_scale(Vector3(0.5, 8.0, 0.5)),
			Vector3(t.x, top + 4.0, t.z) + rot * Vector3(pw * lx, 0.0, 0.0)))
		_steel_c.append(Color(0.30, 0.31, 0.33))
	var ad: Array = ROOF_ADS[rng.randi_range(0, ROOF_ADS.size() - 1)]
	if t.tag == "NEEDLMAN & MARKS":
		ad = ["NEEDLMAN & MARKS", "SINCE 1907 · SECOND FLOOR, ASPIRATION",
			Color(0.13, 0.12, 0.14), Color(0.92, 0.86, 0.66)]
	_panel.append(Transform3D(rot * Basis.from_scale(Vector3(pw, ph, 0.5)),
		Vector3(t.x, py, t.z)))
	_panel_c.append((ad[2] as Color))
	_steel.append(Transform3D(rot * Basis.from_scale(Vector3(pw, 0.16, 1.1)),
		Vector3(t.x, py - ph * 0.5 - 0.5, t.z) + rot * Vector3(0, 0, 0.45)))
	_steel_c.append(Color(0.26, 0.27, 0.29))
	for k in 3:
		_lit_warm.append(Transform3D(rot * Basis.from_scale(Vector3(0.6, 0.3, 0.4)),
			Vector3(t.x, py - ph * 0.5 - 0.28, t.z)
			+ rot * Vector3(pw * (float(k) - 1.0) * 0.3, 0.0, 0.75)))
	for s: float in [1.0, -1.0]:
		var n := rot * Vector3(0, 0, s * 0.3)
		_label(str(ad[0]), Vector3(t.x, py + ph * 0.16, t.z) + n,
			yaw + (0.0 if s > 0.0 else PI), pw * 0.92, (ad[3] as Color), 190,
			SIGN.HOARDING, ph * 0.40)
		_label(str(ad[1]), Vector3(t.x, py - ph * 0.24, t.z) + n,
			yaw + (0.0 if s > 0.0 else PI), pw * 0.92, (ad[3] as Color), 82,
			SIGN.HOARDING, ph * 0.30)
	if not t.podium:
		_lobby(t, rng)


# =============================== TYPE 7 · SITE ===============================
## A building that is not finished. The lower two fifths are clad and glazed;
## above that it is bare frame and floor plates you can see the sky through,
## wrapped in green safety net, with a tower crane standing in one corner and
## its jib swung out over the street. At 800 m the crane is the only vertical
## in downtown that is not a building, which is exactly the point.
func _build_site(t: Tower, rng: RandomNumberGenerator) -> void:
	var top := BASE_Y + t.h
	var clad := t.h * 0.40
	var conc := Color(0.86, 0.85, 0.82)
	_add(_corp, _corp_c, Vector3(t.sx, clad, t.sz),
		Vector3(t.x, BASE_Y + clad * 0.5, t.z), Color(0.72, 0.76, 0.80))
	_add(_conc, _conc_c, Vector3(t.sx + 0.7, 0.5, t.sz + 0.7),
		Vector3(t.x, BASE_Y + clad, t.z), conc * 0.9)
	# The frame: nine columns and a plate every four metres, no cladding.
	for cx: float in [-1.0, 0.0, 1.0]:
		for cz: float in [-1.0, 0.0, 1.0]:
			_add(_shell, _shell_c, Vector3(0.8, t.h - clad, 0.8),
				Vector3(t.x + cx * (t.sx * 0.5 - 1.0), BASE_Y + clad + (t.h - clad) * 0.5,
					t.z + cz * (t.sz * 0.5 - 1.0)), conc)
	var y := BASE_Y + clad + 4.0
	while y < top:
		_add(_shell, _shell_c, Vector3(t.sx, 0.3, t.sz), Vector3(t.x, y, t.z), conc)
		y += 4.0
	_add(_shell, _shell_c, Vector3(t.sx, 0.4, t.sz), Vector3(t.x, top, t.z), conc)
	_net.append(_xf(Vector3(t.sx + 0.6, 9.0, t.sz + 0.6), Vector3(t.x, top - 4.5, t.z)))
	# Tower crane in the corner of the footprint, jib swung over the block.
	var mx := t.x + t.sx * 0.5 - 1.6
	var mz := t.z - t.sz * 0.5 + 1.6
	var mast := t.h + 24.0
	_add(_steel, _steel_c, Vector3(1.7, mast, 1.7),
		Vector3(mx, BASE_Y + mast * 0.5, mz), Color(0.86, 0.55, 0.10))
	var mtop := BASE_Y + mast
	_add(_steel, _steel_c, Vector3(2.6, 2.4, 2.6), Vector3(mx, mtop + 1.2, mz),
		Color(0.90, 0.88, 0.84))
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	_steel.append(Transform3D(rot * Basis.from_scale(Vector3(1.0, 1.0, 34.0)),
		Vector3(mx, mtop + 2.9, mz) + rot * Vector3(0, 0, 10.0)))
	_steel_c.append(Color(0.86, 0.55, 0.10))
	_steel.append(Transform3D(rot * Basis.from_scale(Vector3(2.6, 1.9, 3.4)),
		Vector3(mx, mtop + 2.9, mz) + rot * Vector3(0, 0, -8.4)))
	_steel_c.append(Color(0.42, 0.42, 0.44))
	var hook := Vector3(mx, mtop + 2.9, mz) + rot * Vector3(0, 0, 19.0)
	_steel.append(Transform3D(Basis.from_scale(Vector3(0.12, 16.0, 0.12)),
		hook - Vector3(0, 8.2, 0)))
	_steel_c.append(Color(0.30, 0.30, 0.32))
	_steel.append(Transform3D(Basis.from_scale(Vector3(0.9, 1.1, 0.9)),
		hook - Vector3(0, 16.6, 0)))
	_steel_c.append(Color(0.36, 0.36, 0.38))
	_lit_red.append(_xf(Vector3(0.8, 0.8, 0.8), Vector3(mx, mtop + 2.9, mz)))
	# Site hoist on one face, and the hoarding round the base.
	var face := signf(_nearest_avenue(t.x) - t.x)
	if face == 0.0:
		face = 1.0
	_add(_steel, _steel_c, Vector3(2.4, t.h * 0.8, 2.4),
		Vector3(t.x + face * (t.sx * 0.5 + 1.4), BASE_Y + t.h * 0.4, t.z + t.sz * 0.3),
		Color(0.40, 0.41, 0.43))
	_add(_panel, _panel_c, Vector3(t.sx + 2.6, 2.8, t.sz + 2.6),
		Vector3(t.x, BASE_Y + 1.4, t.z), Color(0.16, 0.30, 0.22))
	var yaw2 := atan2(face, 0.0)
	var head := "THE CONVENTION CRATER" if t.tag == "THE CONVENTION CRATER" \
		else "PIONEER VISION DEVELOPMENT"
	# Picked from the tower's own grid cell, not the RNG: zero new draws.
	var sub: String = HOARDING_SUBS[(t.col * 3 + t.row) % HOARDING_SUBS.size()]
	if t.tag == "THE CONVENTION CRATER":
		sub = "PHASE I · OPENING 2031 · PROBABLY"
	# The hoarding is 2.8 m tall and wraps the whole base; head and sub share
	# the upper half of it.
	_label(head, Vector3(t.x + face * (t.sx * 0.5 + 1.45), BASE_Y + 2.05, t.z),
		yaw2, t.sz * 1.05, Color(0.95, 0.93, 0.86), 96, SIGN.HOARDING, 0.62)
	_label(SIGN.balance(sub, 2) if sub.length() > 30 else sub,
		Vector3(t.x + face * (t.sx * 0.5 + 1.45), BASE_Y + 1.06, t.z),
		yaw2, t.sz * 1.05, Color(0.72, 0.90, 0.78), 52, SIGN.STENCIL, 0.66)


# ============================== SHARED PIECES ================================
## A two-storey glazed lobby for towers the M1 recipe left podium-less, so no
## type meets the pavement as a bare extruded shaft. Carries a tenant plate.
func _lobby(t: Tower, rng: RandomNumberGenerator) -> void:
	var face := signf(_nearest_avenue(t.x) - t.x)
	if face == 0.0:
		face = 1.0
	_add(_conc, _conc_c, Vector3(t.sx + 1.5, 6.4, t.sz + 1.5),
		Vector3(t.x, BASE_Y + 3.2, t.z), Color(0.62, 0.61, 0.58))
	_add(_panel, _panel_c, Vector3(t.sx + 1.9, 0.4, t.sz + 1.9),
		Vector3(t.x, BASE_Y + 6.5, t.z), Color(0.24, 0.24, 0.26))
	# Glazed bays, proud of the wall (the M14 lesson: flush glazing reads as a
	# hole), and a taller entrance bay on the avenue side.
	for n: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var half_n := absf(n.x) * (t.sx + 1.5) * 0.5 + absf(n.z) * (t.sz + 1.5) * 0.5
		var w := absf(n.x) * (t.sz + 1.5) + absf(n.z) * (t.sx + 1.5)
		var rot := Basis(Vector3.UP, atan2(n.x, n.z))
		_panel.append(Transform3D(rot * Basis.from_scale(Vector3(w - 1.6, 4.4, 0.24)),
			Vector3(t.x + n.x * (half_n + 0.06), BASE_Y + 3.0, t.z + n.z * (half_n + 0.06))))
		_panel_c.append(Color(0.15, 0.18, 0.21))
	var ex := Vector3(face, 0, 0)
	var rot2 := Basis(Vector3.UP, atan2(face, 0.0))
	_add(_conc, _conc_c, Vector3(0.6, 7.4, 6.4),
		Vector3(t.x + face * ((t.sx + 1.5) * 0.5 + 0.2), BASE_Y + 3.7, t.z),
		Color(0.70, 0.68, 0.64))
	_lit_warm.append(Transform3D(rot2 * Basis.from_scale(Vector3(4.6, 0.35, 0.4)),
		Vector3(t.x, BASE_Y + 4.6, t.z) + ex * ((t.sx + 1.5) * 0.5 + 0.45)))
	var tenant: String = LOBBY_TENANTS[rng.randi_range(0, LOBBY_TENANTS.size() - 1)]
	if t.tag != "" and t.tag != "THE MAGNATE BUILDING":
		tenant = t.tag
	_label(tenant, Vector3(t.x, BASE_Y + 6.5, t.z) + ex * ((t.sx + 1.5) * 0.5 + 0.28),
		atan2(face, 0.0), minf(t.sz + 1.0, 14.0), Color(0.92, 0.90, 0.84), 74,
		SIGN.PLAQUE, 0.30)


## A building's name cut into a setback wall, readable from all four sides.
## `frac` is the step's footprint fraction — the letters have to stand PROUD of
## that wall, not at some fraction of the base footprint (round one buried the
## Magnate's name inside its own limestone).
func _crown_name(t: Tower, y: float, text: String, frac: float) -> void:
	for f in 4:
		var ang := float(f) * PI * 0.5
		_label(text, Vector3(t.x + sin(ang) * (t.sx * frac * 0.5 + 0.35),
			y, t.z + cos(ang) * (t.sz * frac * 0.5 + 0.35)), ang,
			minf(t.sx, t.sz) * frac * 0.94, Color(0.94, 0.88, 0.66), 150,
			SIGN.CHANNEL)


func _nearest_avenue(x: float) -> float:
	var best := NS_X[0]
	for a: float in NS_X:
		if absf(a - x) < absf(best - x):
			best = a
	return best


## The M8 district gradient survives the re-skin: cool corporate blue in the
## north rows, warm bronze toward the strip in the south. Applied as a gentle
## multiplier so no instance colour crosses 1.0 (the HDR law: >1 reads as glow).
func _warmth(t: Tower, base: Color, amount: float) -> Color:
	var w := clampf((float(t.row) - 1.0) / 4.0, 0.0, 1.0)
	var c := base * Color(1.0 - amount * (1.0 - w) * 0.4, 1.0 - amount * 0.25,
		1.0 - amount * w)
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


func _xf(size: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)


func _add(list: Array[Transform3D], cols: Array[Color], size: Vector3, pos: Vector3,
		col: Color) -> void:
	list.append(Transform3D(Basis.from_scale(size), pos))
	cols.append(Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0), 1.0))


## M22: exact fit (see `sign_kit.gd`; the house 0.66 estimate is retired), and
## a REGISTER per surface. Downtown's whole problem was that a hand-painted
## ghost sign, a bank lobby plaque, a stone entablature and a construction
## hoarding were the same label at four sizes. They are now four different
## hands: GHOST leans and spaces out with no outline, PLAQUE is light and
## luxuriously tracked, MARQUEE is heavy and tight, HOARDING is bold and
## crowded. One font, zero asset files.
func _label(text: String, pos: Vector3, yaw: float, max_w: float, col: Color,
		cap: int, style: int = SIGN.HOARDING, max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, cap)
	# Alpha scissor, not alpha blend: 142 signs in the sorted transparent pass
	# is real frame time, and cut-out text on a facade loses nothing.
	lbl.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)


# ================================= FLUSH =====================================
## One MultiMesh per element class: seventeen draw calls carry 108 buildings.
func _flush(towers: Array[Tower]) -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var drum: ArrayMesh = MESH_KIT.prism(1.0, 1.0, 10)
	# SHADOWS ARE THE BUDGET. A MultiMesh is culled as ONE unit, so every set
	# is submitted to every directional-shadow cascade every frame. Round
	# one shipped all 4.6 k instances as shadow casters and cost 5-6 ms/frame at
	# street level (measured A/B). Only the BUILDING MASSES cast; trim, glazing,
	# lights, signage and the cars parked inside a garage do not — none of them
	# produces a shadow a player could name.
	_mm(unit, _corp, _corp_c, TEX.dark_curtain_material(Color(0.30, 0.36, 0.44)), "TypeCorpGlass", true)
	_mm(unit, _deco, _deco_c, TEX.deco_stone_material(Color(0.76, 0.72, 0.63)), "TypeDecoStone", true)
	_mm(unit, _ribbon, _ribbon_c, TEX.slab_ribbon_material(Color(0.80, 0.79, 0.75)), "TypeSlabRibbon", true)
	_mm(unit, _masonry, _masonry_c, TEX.masonry_window_material(Color(0.50, 0.29, 0.22)), "TypeBrickWall", true)
	_mm(unit, _block, _block_c, TEX.painted_block_material(), "TypePaintedBlock", true)
	_mm(unit, _conc, _conc_c, TEX.board_concrete_material(), "TypeConcrete", true)
	_mm(unit, _shell, _shell_c, TEX.board_concrete_material(), "TypeDeckShell", false)
	_mm(unit, _steel, _steel_c, _plain(0.55, 0.35), "TypeSteel", false)
	_mm(unit, _panel, _panel_c, _plain(0.80, 0.0), "TypePanels", false)
	_mm(unit, _cars, _cars_c, _plain(0.42, 0.25), "TypeDeckCars", false)
	_mm(drum, _tanks, [], _solid(Color(0.44, 0.42, 0.38), 0.9), "TypeWaterTanks", false)
	_m_cool = _glow(LIT_COOL, NIGHT_E[0])
	_m_warm = _glow(LIT_WARM, NIGHT_E[1])
	_m_tube = _glow(LIT_TUBE, NIGHT_E[2])
	_m_red = _glow(LIT_RED, NIGHT_E[3])
	_m_neon = _glow(LIT_NEON, NIGHT_E[4])
	_mm(unit, _lit_cool, [], _m_cool, "TypeCrownLightsCool", false)
	_mm(unit, _lit_warm, [], _m_warm, "TypeCrownLightsWarm", false)
	_mm(unit, _lit_tube, [], _m_tube, "TypeDeckTubes", false)
	_mm(unit, _lit_red, [], _m_red, "TypeWarningLights", false)
	_mm(unit, _neon, [], _m_neon, "TypeNeonMustang", false)
	_mm(unit, _net, [], _mesh_net(), "TypeSafetyNet", false)
	_report(towers)


## One line in the boot log, in the house convention (POOLS:, SUBURB NIGHT:) —
## the type census and the instance/draw-call cost, so the budget is auditable
## without a probe.
func _report(towers: Array[Tower]) -> void:
	var n := [0, 0, 0, 0, 0, 0, 0]
	for t in towers:
		n[t.kind] += 1
	var inst := _corp.size() + _deco.size() + _ribbon.size() + _masonry.size() \
		+ _block.size() + _conc.size() + _shell.size() + _steel.size() + _panel.size() \
		+ _cars.size() + _tanks.size() + _lit_cool.size() + _lit_warm.size() \
		+ _lit_tube.size() + _lit_red.size() + _neon.size() + _net.size()
	var batches := 0
	var labels := 0
	for c in get_children():
		if c is MultiMeshInstance3D:
			batches += 1
		elif c is Label3D:
			labels += 1
	print("DOWNTOWN TYPES: %d towers = corp %d / deco %d / slab %d / brick %d / deck %d / signblock %d / site %d — %d instances in %d MultiMeshes + %d signs" % [
		towers.size(), n[Kind.CORP], n[Kind.DECO], n[Kind.MIDSLAB], n[Kind.BRICK],
		n[Kind.DECK], n[Kind.SIGNBLOCK], n[Kind.SITE], inst, batches, labels])


func _plain(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	return m


func _solid(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _mesh_net() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.52, 0.34, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	return m


func _mm(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color],
		mat: StandardMaterial3D, label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
