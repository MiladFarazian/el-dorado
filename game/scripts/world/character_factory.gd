extends RefCounted
## CHARACTER FACTORY — the people of the Megaplex.
## M9 built them, M10 rigged them, M15 rounded them, M16 made them REAL.
## Builds a jointed humanoid out of spheres, tapered round limbs and boxes and
## RETURNS A RIG — a dictionary of the joint nodes — so callers can drive a
## procedural walk cycle with `animate()`.
##
## ANATOMY (feet at y=0, ~1.77 m tall at scale 1.0): shoes with a heel and a
## toe box, tapered shins with a calf belly, thighs with a hip socket, a pelvis
## with a seat, a torso with real CHEST DEPTH (pec swell forward, scapula plane
## aft), a trapezius that carries the neck INTO the collar, deltoid mass at
## each arm root, and a head with a jaw, chin, cheekbones, ears, a brow ridge,
## a three-part nose, a mouth, and two-layer eyes (sclera + iris under a lid).
##
## WARDROBE IS A SYSTEM, not a shirt colour. Eight outfit archetypes — casual,
## western, hi-vis worker, office, service, streetwear, scrubs, gameday — each
## assembled from layered pieces: collars (crew/snap/polo/dress/v-neck/hood),
## sleeve cuffs, an untucked hem that overlaps the pants, belts with buckles,
## chest pockets, vests, aprons, hoods, ties, badges. Every pedestrian is
## somebody with a job you can read at a glance (canon rule 3: rendered with
## warmth, and nobody is a joke).
##
## RIG hierarchy — rotations are all the animator touches (FROZEN CONTRACT):
##   root_vis (bob + lean)
##     hip_0/hip_1  -> knee_0/knee_1
##     torso -> collar -> neck_head
##            -> sh_0/sh_1 -> el_0/el_1
## Every joint pivot sits at the same local offset it has since M10, so melee,
## movement and combat code that reaches into the rig keeps working.
##
## The caller's COLLIDER is untouched (everything fits the same 1.75 m
## envelope). Costume draws come from the CALLER's RNG and the draw COUNT is
## unchanged since M9 — all the new variety rides a local RNG seeded from
## those draws, so pedestrians/carjack/foot_cops streams never shift.

const KIT := preload("res://scripts/world/mesh_kit.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

static var _mats: Dictionary = {}

enum Hat { NONE, CAP, COWBOY, FLAT_BRIM, HARD_HAT, BEANIE }
enum Outfit { CASUAL, WESTERN, WORKER, OFFICE, SERVICE, STREET, SCRUBS, GAMEDAY }
enum Neck { CREW, SNAP, POLO, DRESS, VEE, HOODED }
enum Hairdo { BALD, BUZZ, SHORT, WAVY, AFRO, TIED, LONG }
enum Whiskers { CLEAN, STUBBLE, MUSTACHE, GOATEE, FULL }
enum Shoe { BOOT, SNEAKER, DRESS, CLOG }

# The Megaplex, in skin tones — deep to pale, warm all the way through.
const SKIN_TONES: Array[Color] = [
	Color(0.28, 0.17, 0.12), Color(0.36, 0.23, 0.16), Color(0.46, 0.31, 0.21),
	Color(0.57, 0.40, 0.28), Color(0.66, 0.48, 0.34), Color(0.74, 0.56, 0.42),
	Color(0.82, 0.66, 0.52), Color(0.89, 0.75, 0.63)]
const SHIRTS: Array[Color] = [
	Color(0.20, 0.55, 0.55), Color(0.70, 0.32, 0.18), Color(0.78, 0.64, 0.20),
	Color(0.30, 0.42, 0.65), Color(0.48, 0.58, 0.42), Color(0.52, 0.32, 0.52),
	Color(0.85, 0.82, 0.75), Color(0.25, 0.25, 0.28), Color(0.62, 0.15, 0.18),
	Color(0.34, 0.55, 0.38), Color(0.90, 0.88, 0.84), Color(0.16, 0.30, 0.42)]
const PANTS: Array[Color] = [
	Color(0.18, 0.22, 0.34), Color(0.15, 0.17, 0.24), Color(0.30, 0.26, 0.20),
	Color(0.24, 0.24, 0.26), Color(0.45, 0.40, 0.32), Color(0.22, 0.28, 0.40),
	Color(0.13, 0.13, 0.15)]
const HAT_COLORS: Array[Color] = [
	Color(0.14, 0.12, 0.10), Color(0.55, 0.45, 0.30), Color(0.30, 0.30, 0.33),
	Color(0.60, 0.20, 0.15), Color(0.20, 0.30, 0.50), Color(0.78, 0.72, 0.58)]
const HAIRS: Array[Color] = [
	Color(0.05, 0.04, 0.035), Color(0.10, 0.07, 0.05), Color(0.19, 0.12, 0.07),
	Color(0.30, 0.18, 0.10), Color(0.35, 0.24, 0.13), Color(0.46, 0.34, 0.18),
	Color(0.58, 0.47, 0.30)]
const GRAY_HAIR := Color(0.70, 0.68, 0.66)
const EYE_COLORS: Array[Color] = [
	Color(0.13, 0.08, 0.05), Color(0.13, 0.08, 0.05), Color(0.22, 0.14, 0.07),
	Color(0.22, 0.14, 0.07), Color(0.34, 0.27, 0.13), Color(0.26, 0.36, 0.28),
	Color(0.30, 0.42, 0.50), Color(0.42, 0.44, 0.44)]
const SCLERA := Color(0.74, 0.71, 0.68)   # M24: was 0.84/0.82/0.79 — with 0.13 emission the whites read startled at `face`
# Hi-vis is a legal colour, not a fashion choice: ANSI yellow-green and orange.
const HIVIS: Array[Color] = [Color(0.86, 0.90, 0.16), Color(0.95, 0.45, 0.06)]
const REFLECTIVE := Color(0.80, 0.83, 0.86)
const SCRUB_COLORS: Array[Color] = [
	Color(0.18, 0.44, 0.45), Color(0.16, 0.22, 0.36), Color(0.42, 0.58, 0.72),
	Color(0.40, 0.16, 0.22), Color(0.42, 0.50, 0.42), Color(0.44, 0.46, 0.50)]
const APRON_COLORS: Array[Color] = [
	Color(0.13, 0.14, 0.16), Color(0.50, 0.18, 0.15), Color(0.70, 0.66, 0.56),
	Color(0.18, 0.32, 0.28)]
const TEAM_COLORS: Array[Color] = [  # Rustlers / Bolo Capital / Pecos Bullet
	Color(0.10, 0.20, 0.45), Color(0.62, 0.14, 0.16), Color(0.10, 0.34, 0.24),
	Color(0.86, 0.52, 0.10)]
const DRESS_SHIRTS: Array[Color] = [
	Color(0.90, 0.91, 0.93), Color(0.72, 0.80, 0.88), Color(0.86, 0.86, 0.82),
	Color(0.60, 0.68, 0.78), Color(0.84, 0.78, 0.76)]
const SLACKS: Array[Color] = [
	Color(0.18, 0.19, 0.22), Color(0.26, 0.26, 0.29), Color(0.22, 0.24, 0.30),
	Color(0.34, 0.31, 0.26)]
const TIE_COLORS: Array[Color] = [
	Color(0.48, 0.12, 0.16), Color(0.14, 0.20, 0.38), Color(0.20, 0.34, 0.30),
	Color(0.36, 0.26, 0.14)]
const BOOT := Color(0.18, 0.12, 0.09)
const LEATHER := Color(0.14, 0.11, 0.10)
const COP_SHIRT := Color(0.12, 0.16, 0.34)
const COP_PANTS := Color(0.09, 0.11, 0.20)
const DUTY_BLACK := Color(0.07, 0.07, 0.08)

# ---- gait tuning (all in the animator) ----
const STRIDE_PER_M := 1.15          # gait radians per metre travelled
const HIP_SWING := 0.62             # rad at full running speed
const KNEE_BEND := 0.95
const ARM_SWING := 0.5
const ELBOW_BEND := 0.45
const BOB_H := 0.045                # vertical bounce (m)
const LEAN_MAX := 0.16              # forward lean at speed (rad)
const BLEND := 12.0                 # pose exp-decay rate toward target
const REF_SPEED := 6.5              # m/s that counts as "full sprint"

# ---- frozen joint pivots (M10 contract — callers reach into these) ----
const HIP_PIVOT := Vector3(0.10, 0.90, 0.0)   # x mirrored per side
const KNEE_PIVOT := Vector3(0.0, -0.43, 0.0)
const TORSO_PIVOT := Vector3(0.0, 0.90, 0.0)
const COLLAR_PIVOT := Vector3(0.0, 0.56, 0.0)
const HEAD_PIVOT := Vector3(0.0, 0.08, 0.0)
const SHOULDER_X := 0.183                     # × build; mirrored per side
const ELBOW_PIVOT := Vector3(0.0, -0.30, 0.0)


# ============================== CONFIGS ======================================
## Roll a pedestrian. The CALLER's stream contributes exactly EIGHT draws, in
## the same order it has since M9 — every richer choice below rides a local RNG
## seeded from those eight, so no caller's sequence ever shifts.
static func random_config(rng: RandomNumberGenerator) -> Dictionary:
	var hat_roll := rng.randf()
	var i_skin := rng.randi_range(0, SKIN_TONES.size() - 1)
	var i_shirt := rng.randi_range(0, SHIRTS.size() - 1)
	var i_pants := rng.randi_range(0, PANTS.size() - 1)
	var i_hair := rng.randi_range(0, HAIRS.size() - 1)
	var i_hatc := rng.randi_range(0, HAT_COLORS.size() - 1)
	var height := rng.randf_range(0.89, 1.07)
	var frame := rng.randf_range(0.92, 1.12)

	var r := RandomNumberGenerator.new()
	r.seed = hash("ped|%d|%d|%d|%d|%d|%.6f|%.6f|%.6f" % [i_skin, i_shirt,
		i_pants, i_hair, i_hatc, hat_roll, height, frame])

	var cfg := _person(r, SKIN_TONES[i_skin], HAIRS[i_hair], height, frame)
	cfg["shirt"] = SHIRTS[i_shirt]
	cfg["pants"] = PANTS[i_pants]
	cfg["hat_color"] = HAT_COLORS[i_hatc]
	_dress(cfg, r, _pick_outfit(r))
	return cfg


## A Dorado PD officer: same anatomy, duty uniform. Caller stream: THREE draws,
## unchanged since M9.
static func cop_config(rng: RandomNumberGenerator) -> Dictionary:
	var i_skin := rng.randi_range(0, SKIN_TONES.size() - 1)
	var i_hair := rng.randi_range(0, HAIRS.size() - 1)
	var height := rng.randf_range(0.97, 1.04)

	var r := RandomNumberGenerator.new()
	r.seed = hash("cop|%d|%d|%.6f" % [i_skin, i_hair, height])

	var cfg := _person(r, SKIN_TONES[i_skin], HAIRS[i_hair], height, 1.08)
	cfg["girth"] = r.randf_range(0.98, 1.16)
	cfg["shirt"] = COP_SHIRT
	cfg["pants"] = COP_PANTS
	cfg["hat"] = Hat.CAP
	cfg["hat_color"] = COP_PANTS
	cfg["outfit"] = Outfit.OFFICE
	cfg["neck"] = Neck.DRESS
	cfg["sleeve_long"] = false
	cfg["tucked"] = true
	cfg["belt"] = true
	cfg["belt_color"] = DUTY_BLACK
	cfg["shoe"] = Shoe.BOOT
	cfg["shoe_color"] = DUTY_BLACK
	cfg["pocket"] = true
	cfg["duty"] = true          # badge chip, name tape, belt gear, epaulets
	cfg["hairdo"] = Hairdo.BUZZ if cfg["hairdo"] == Hairdo.AFRO else cfg["hairdo"]
	cfg["whiskers"] = Whiskers.CLEAN if int(cfg["whiskers"]) == Whiskers.FULL \
		else cfg["whiskers"]
	return cfg


## Book Reyes — pearl snaps, dark denim, boots, charcoal flat-brim, and a
## buckle that outshines his bank account. Defined ONCE, here.
static func book_config() -> Dictionary:
	return {
		"skin": Color(0.55, 0.38, 0.26), "shirt": Color(0.72, 0.68, 0.58),
		"pants": Color(0.14, 0.16, 0.24), "hair": Color(0.07, 0.05, 0.04),
		"hat": Hat.FLAT_BRIM, "hat_color": Color(0.16, 0.15, 0.14),
		"scale": 1.0, "build": 1.06, "girth": 1.02,
		"outfit": Outfit.WESTERN, "neck": Neck.SNAP, "sleeve_long": true,
		"tucked": true, "belt": true, "belt_color": Color(0.24, 0.14, 0.08),
		"buckle": true, "pocket": true, "snaps": true, "yoke": true,
		"shoe": Shoe.BOOT, "shoe_color": Color(0.27, 0.16, 0.09),
		"hairdo": Hairdo.SHORT, "whiskers": Whiskers.STUBBLE,
		"eye": Color(0.21, 0.13, 0.07), "gray": 0.0, "skin_rough": 0.74,
		"brow": 1.08, "nose": 1.05, "jaw": 1.10, "cheek": 1.05,
		"asym": -0.55,        # left brow rides higher — he was born skeptical
		"accent": Color(0.72, 0.70, 0.66),
	}


## Shared human variation: the parts that have nothing to do with a wardrobe.
static func _person(r: RandomNumberGenerator, skin: Color, hair: Color,
		height: float, frame: float) -> Dictionary:
	var gray := 0.0
	var age_roll := r.randf()
	if age_roll > 0.86:
		gray = r.randf_range(0.55, 1.0)      # silver
	elif age_roll > 0.72:
		gray = r.randf_range(0.15, 0.45)     # salt and pepper
	var hairdo: int = [Hairdo.BALD, Hairdo.BUZZ, Hairdo.SHORT, Hairdo.SHORT,
		Hairdo.WAVY, Hairdo.AFRO, Hairdo.TIED, Hairdo.LONG][r.randi_range(0, 7)]
	var whiskers: int = Whiskers.CLEAN
	var wr := r.randf()
	if wr > 0.88: whiskers = Whiskers.FULL
	elif wr > 0.78: whiskers = Whiskers.GOATEE
	elif wr > 0.70: whiskers = Whiskers.MUSTACHE
	elif wr > 0.48: whiskers = Whiskers.STUBBLE
	# a hair of per-person skin drift so six tones read as a hundred people
	var tone := skin.lerp(Color(1, 1, 1), r.randf_range(-0.05, 0.05))
	return {
		"skin": Color(clampf(tone.r, 0.0, 1.0), clampf(tone.g, 0.0, 1.0),
			clampf(tone.b, 0.0, 1.0)),
		"hair": hair.lerp(GRAY_HAIR, gray),
		"gray": gray,
		"scale": height,
		"build": frame,
		"girth": r.randf_range(0.86, 1.30),   # heaviness: radii + torso depth
		"hairdo": hairdo,
		"whiskers": whiskers,
		# skin is not one material: a weathered roofer and a kid out of an
		# air-conditioned office scatter light differently. Local RNG, so no
		# caller's stream moves.
		"skin_rough": r.randf_range(0.60, 0.88),
		"eye": EYE_COLORS[r.randi_range(0, EYE_COLORS.size() - 1)],
		"brow": r.randf_range(0.80, 1.25),
		"nose": r.randf_range(0.82, 1.22),
		"jaw": r.randf_range(0.85, 1.18),
		"cheek": r.randf_range(0.85, 1.18),
		# −1..1: which way this face is NOT symmetrical (brow height, mouth
		# corner). Local RNG, so no caller's stream moves.
		"asym": r.randf_range(-1.0, 1.0),
	}


static func _pick_outfit(r: RandomNumberGenerator) -> int:
	var v := r.randf()
	if v < 0.24: return Outfit.CASUAL
	if v < 0.37: return Outfit.WESTERN
	if v < 0.50: return Outfit.OFFICE
	if v < 0.62: return Outfit.WORKER
	if v < 0.73: return Outfit.STREET
	if v < 0.83: return Outfit.SERVICE
	if v < 0.92: return Outfit.GAMEDAY
	return Outfit.SCRUBS


## Wardrobe archetypes. Each one picks its own fabric, layers, shoes and hat —
## the shirt/pants colours rolled from the caller's stream are a starting point
## an archetype is free to override (a surgeon does not wear a mustard polo).
static func _dress(cfg: Dictionary, r: RandomNumberGenerator, outfit: int) -> void:
	cfg["outfit"] = outfit
	cfg["neck"] = Neck.CREW
	cfg["sleeve_long"] = r.randf() < 0.35
	cfg["tucked"] = false
	cfg["belt"] = false
	cfg["belt_color"] = LEATHER
	cfg["shoe"] = Shoe.SNEAKER
	cfg["shoe_color"] = Color(0.80, 0.78, 0.74) if r.randf() < 0.4 else LEATHER
	cfg["accent"] = Color(0.92, 0.92, 0.90)
	cfg["hat"] = Hat.NONE
	var shirt: Color = cfg["shirt"]

	match outfit:
		Outfit.CASUAL:
			cfg["neck"] = Neck.POLO if r.randf() < 0.35 else Neck.CREW
			cfg["pocket"] = r.randf() < 0.25
			cfg["belt"] = r.randf() < 0.4
			cfg["tucked"] = r.randf() < 0.2
			if r.randf() < 0.18: cfg["shoe"] = Shoe.BOOT
			var h := r.randf()
			if h < 0.24: cfg["hat"] = Hat.CAP
			elif h < 0.33: cfg["hat"] = Hat.COWBOY

		Outfit.WESTERN:
			cfg["shirt"] = shirt.lerp(Color(1, 1, 1), 0.28)   # sun-faded snap shirt
			cfg["pants"] = [Color(0.15, 0.18, 0.28), Color(0.22, 0.26, 0.36),
				Color(0.32, 0.28, 0.22)][r.randi_range(0, 2)]
			cfg["neck"] = Neck.SNAP
			cfg["sleeve_long"] = r.randf() < 0.75
			cfg["tucked"] = true
			cfg["belt"] = true
			cfg["belt_color"] = Color(0.26, 0.16, 0.09)
			cfg["buckle"] = true
			cfg["snaps"] = true
			cfg["yoke"] = r.randf() < 0.6
			cfg["pocket"] = true
			cfg["shoe"] = Shoe.BOOT
			cfg["shoe_color"] = [Color(0.30, 0.18, 0.10), Color(0.20, 0.13, 0.09),
				Color(0.44, 0.30, 0.16)][r.randi_range(0, 2)]
			var hw := r.randf()
			cfg["hat"] = Hat.COWBOY if hw < 0.62 else \
				(Hat.FLAT_BRIM if hw < 0.84 else Hat.CAP)
			cfg["hat_color"] = [Color(0.78, 0.70, 0.52), Color(0.16, 0.14, 0.12),
				Color(0.42, 0.30, 0.20), Color(0.90, 0.86, 0.74)][r.randi_range(0, 3)]

		Outfit.WORKER:
			cfg["shirt"] = [Color(0.55, 0.58, 0.60), Color(0.30, 0.36, 0.46),
				Color(0.72, 0.68, 0.58), Color(0.24, 0.26, 0.28)][r.randi_range(0, 3)]
			cfg["pants"] = [Color(0.30, 0.26, 0.19), Color(0.20, 0.22, 0.30),
				Color(0.34, 0.32, 0.28)][r.randi_range(0, 2)]
			cfg["neck"] = Neck.CREW
			cfg["sleeve_long"] = r.randf() < 0.5
			cfg["tucked"] = true
			cfg["belt"] = true
			cfg["vest"] = r.randf() < 0.78
			cfg["vest_color"] = HIVIS[r.randi_range(0, 1)]
			cfg["pocket"] = true
			cfg["shoe"] = Shoe.BOOT
			cfg["shoe_color"] = Color(0.30, 0.20, 0.11)
			cfg["gloves"] = r.randf() < 0.45
			var hh := r.randf()
			cfg["hat"] = Hat.HARD_HAT if hh < 0.56 else \
				(Hat.CAP if hh < 0.9 else Hat.NONE)
			cfg["hat_color"] = [Color(0.92, 0.78, 0.10), Color(0.90, 0.90, 0.88),
				Color(0.90, 0.42, 0.08)][r.randi_range(0, 2)] \
				if int(cfg["hat"]) == Hat.HARD_HAT else cfg["hat_color"]

		Outfit.OFFICE:
			cfg["shirt"] = DRESS_SHIRTS[r.randi_range(0, DRESS_SHIRTS.size() - 1)]
			cfg["pants"] = SLACKS[r.randi_range(0, SLACKS.size() - 1)]
			cfg["neck"] = Neck.DRESS
			cfg["sleeve_long"] = r.randf() < 0.7
			cfg["tucked"] = true
			cfg["belt"] = true
			cfg["belt_color"] = Color(0.16, 0.12, 0.10)
			cfg["pocket"] = r.randf() < 0.4
			cfg["shoe"] = Shoe.DRESS
			cfg["shoe_color"] = Color(0.12, 0.10, 0.09)
			cfg["tie"] = r.randf() < 0.45
			cfg["tie_color"] = TIE_COLORS[r.randi_range(0, TIE_COLORS.size() - 1)]
			cfg["lanyard"] = r.randf() < 0.35
			if r.randf() < 0.12: cfg["hat"] = Hat.CAP

		Outfit.SERVICE:
			cfg["neck"] = Neck.CREW if r.randf() < 0.6 else Neck.POLO
			cfg["tucked"] = true
			cfg["apron"] = true
			cfg["apron_color"] = APRON_COLORS[r.randi_range(0, APRON_COLORS.size() - 1)]
			cfg["belt"] = true
			cfg["shoe"] = Shoe.SNEAKER
			cfg["shoe_color"] = Color(0.14, 0.13, 0.13)
			cfg["hat"] = Hat.CAP if r.randf() < 0.7 else Hat.NONE

		Outfit.STREET:
			cfg["neck"] = Neck.HOODED if r.randf() < 0.62 else Neck.CREW
			cfg["sleeve_long"] = int(cfg["neck"]) == Neck.HOODED or r.randf() < 0.4
			cfg["hood_up"] = int(cfg["neck"]) == Neck.HOODED and r.randf() < 0.32
			cfg["pants"] = [Color(0.13, 0.13, 0.15), Color(0.20, 0.22, 0.28),
				Color(0.35, 0.34, 0.32), Color(0.17, 0.20, 0.30)][r.randi_range(0, 3)]
			cfg["shoe"] = Shoe.SNEAKER
			cfg["shoe_color"] = [Color(0.88, 0.87, 0.84), Color(0.10, 0.10, 0.11),
				Color(0.70, 0.20, 0.18)][r.randi_range(0, 2)]
			cfg["accent"] = Color(0.90, 0.90, 0.88)
			var hs := r.randf()
			if not bool(cfg.get("hood_up", false)):
				if hs < 0.42: cfg["hat"] = Hat.CAP
				elif hs < 0.58: cfg["hat"] = Hat.BEANIE

		Outfit.SCRUBS:
			var sc: Color = SCRUB_COLORS[r.randi_range(0, SCRUB_COLORS.size() - 1)]
			cfg["shirt"] = sc
			cfg["pants"] = sc.darkened(0.06)
			cfg["neck"] = Neck.VEE
			cfg["sleeve_long"] = false
			cfg["tucked"] = false
			cfg["pocket"] = true
			cfg["lanyard"] = true
			cfg["shoe"] = Shoe.CLOG
			cfg["shoe_color"] = Color(0.86, 0.86, 0.84)
			cfg["accent"] = sc.lightened(0.25)
			if r.randf() < 0.18: cfg["hat"] = Hat.CAP

		Outfit.GAMEDAY:
			var tc: Color = TEAM_COLORS[r.randi_range(0, TEAM_COLORS.size() - 1)]
			cfg["shirt"] = tc
			cfg["accent"] = Color(0.92, 0.90, 0.86)
			cfg["neck"] = Neck.CREW
			cfg["sleeve_long"] = false
			cfg["jersey"] = true
			cfg["shorts"] = r.randf() < 0.45
			cfg["pants"] = Color(0.24, 0.25, 0.28) if bool(cfg["shorts"]) \
				else cfg["pants"]
			cfg["shoe"] = Shoe.SNEAKER
			cfg["shoe_color"] = Color(0.88, 0.87, 0.84)
			cfg["hat"] = Hat.CAP if r.randf() < 0.68 else Hat.NONE
			cfg["hat_color"] = tc


# ============================== BUILD ========================================
## Assemble under `root`; `feet_y` is where the figure's feet sit in the
## caller's local space (0 for feet-origin bodies, -0.875 for centred ones).
## Returns the rig dictionary — hand it back to animate() every frame.
static func build(root: Node3D, cfg: Dictionary, feet_y: float) -> Dictionary:
	var s := float(cfg.get("scale", 1.0))
	var w := float(cfg.get("build", 1.0))        # frame width (shoulder span)
	var g := float(cfg.get("girth", 1.0))        # heaviness (radii + depth)
	var lg := 1.0 + (g - 1.0) * 0.55             # limb thickness factor

	var vis := Node3D.new()
	vis.name = "Body"
	vis.position = Vector3(0, feet_y, 0)
	vis.scale = Vector3(s, s, s)
	root.add_child(vis)

	var rig := {"vis": vis, "phase": 0.0, "bob": 0.0, "lean": 0.0}
	var masses := _torso_masses(w, g)
	_build_legs(vis, rig, cfg, lg)
	var torso := _build_torso(vis, rig, cfg, w, g, masses)
	var collar: Node3D = rig["collar"]
	_build_head(rig["head"], cfg)
	_build_arms(collar, rig, cfg, w, lg)
	_build_layers(torso, collar, rig, cfg, w, g, masses)
	return rig


# ===================== THE BODY SURFACE (mount points) =======================
## D-020 closed the elbow-sign bug but left one complaint open: "wardrobe panels
## float". They floated because a pocket was placed on a PLANE at a fixed z
## while the shirt under it is a barrel that curves away — measured on the
## narrowed M16/D-020 torso, a chest pocket's outer edge stood 2.9 cm off the
## shirt. The fix is that the torso's masses are declared ONCE here; the build
## EMITS them and `_surface()` EVALUATES them, so a flat piece can be laid on
## the real surface along the real normal instead of guessed at.
##
## Entry shapes (kept as plain Arrays — this runs once per character):
##   ["limb", r_bottom, r_top, y_bottom, y_top, z_scale, z_centre, mat_id]
##   ["ball", centre: Vector3, diameters: Vector3, mat_id]
## mat_id 0 = pants (pelvis), 1 = shirt.
static func _torso_masses(w: float, g: float) -> Array:
	var dep := clampf(0.74 + (g - 1.0) * 0.50, 0.66, 0.94)   # chest DEPTH factor
	var belly := 1.0 + (g - 1.0) * 0.85
	# M20 — GIRTH-CONDITIONAL MASSES. The pec, the waist and the seat were
	# authored at girth 1.0 while the barrel's own depth scales with `dep`, so
	# they came apart at both ends of the roll: measured at girth 0.86 the pec
	# stood 28.1 mm proud and the waist 20.8 mm (that IS the "wavy horizontal
	# ridge across the shirt" M18 believed it had removed — it was simply
	# invisible on the neutral build it was checked against), and at girth 1.30
	# the pec was 27.3 mm INSIDE the barrel, i.e. the chest swell "the side view
	# lives or dies on" did not exist on heavy peds at all.
	# Each of the three is now SOLVED from the barrel it sits on, so its relief
	# is a constant few millimetres at every build/girth corner instead of a
	# fixed offset that only happens to be right in the middle of the range.
	var chest_f := 0.150 * w * dep                 # barrel front at chest height
	var pec_d := 0.2054 * dep                      # pec depth tracks that
	var ab_r := 0.1457 * w * belly * (dep + 0.055)  # abdomen front at the waist
	var wst_d := 0.2805 * belly * (dep + 0.055)
	return [
		# THE PELVIS, M21 — this is D-028's real root cause and it was mis-filed.
		# The ledger blamed "the untucked-hem wardrobe piece"; Book is
		# `tucked: true` and never draws one. What renders as "a hard-edged navy
		# peplum standing off the trousers" is THIS mass. Until now it was ONE
		# limb running y −0.085 → 0.190 with r 0.190·w·g at the BOTTOM and
		# 0.150·w·k at the top — an INVERTED cone, widest at its lowest ring,
		# closed there by `round_limb`'s flat cap. Measured on Book: a 411 mm-wide
		# disc at y 0.815 m with 205 mm-wide thighs hanging out of it, i.e. a
		# 103 mm horizontal ledge all the way round. That is a skirt, and it is
		# the single loudest silhouette error in `back`, `side` and `torso`.
		#
		# A pelvis is widest at the trochanter and tapers BOTH ways. Two limbs:
		# one flaring down from the waist to the widest ring, one tapering from
		# there into the thighs and ending small enough that its cap is buried
		# between them (bottom radius × the depth factor is solved against the
		# thigh's own half-depth at that height, so the cap cannot surface at any
		# girth). The seat rides on the lower limb's z-centre — a real backside is
		# the pelvis being deeper behind than in front, not a ball stuck on it.
		["limb", 0.196 * w * g, 0.150 * w * (1.0 + (g - 1.0) * 0.72),
			0.010, 0.190, dep + 0.075, 0.0, 0],
		# The lower cone's bottom radius is a CONSTANT, not w·g: the legs are not
		# scaled by build or girth either (HIP_PIVOT.x and the thigh radii ride
		# `lg`), so a w·g bottom would break out of the thighs at the heavy corner.
		# It STOPS at y −0.060 for a reason found by screenshot, not by arithmetic:
		# round one ran it to −0.165, and a dark trouser tapering inward is a
		# DOWNWARD-facing surface — with the sun at 64° it went black, and the
		# black showed through the gap between the thighs as a brief. −0.060 is
		# exactly where the two thigh tubes close on each other (inner edges at
		# |x| 0.003 at every girth in the roll), so the taper ends the instant
		# there is no longer a gap to see through.
		["limb", 0.130, 0.196 * w * g, -0.060, 0.010, dep + 0.075, 0.0, 0],
		# D-004 — the glutes read as a rounded MASS from `back`. Measured, they
		# were a 22 mm-proud 260 mm-tall ellipsoid whose bottom hung clear of the
		# pelvis barrel: an object with its own silhouette, which is exactly what
		# "a mass" means. (Round 1 of this fix split it into two cheeks with a
		# cleft and that was worse — two silhouettes instead of one; the
		# screenshot killed it.) It is now ONE swell, solved to stand 8 mm proud
		# at EVERY girth instead of 22–33, flattened to 180 mm and tucked inside
		# the pelvis top and bottom so it has no free edge to draw at all.
		# ...and the seat ball itself is GONE. Three rounds of screenshots said
		# the same thing the head said: an ellipsoid laid on a barrel shows its
		# crossing curve, and no amount of flattening hides it — at 22 mm proud
		# it was a bubble, at 10 mm two cheeks, at 5 mm two crescents where its
		# lateral extremes cut the pelvis silhouette. The pelvis taper carries
		# the seat now. HONEST COST: from `side` the glutes are a taper rather
		# than a swell; a real seat wants the pelvis re-topologised as one swept
		# shell the way the head was, which is the next character milestone.
		# abdomen and thorax: a barrel with a WAIST, not a plank
		# M20: this ran at dep+0.08 against the section above it at dep+0.03,
		# which is a 7.4 mm backward step in the front silhouette at y 0.302
		# (10.7 mm on the heaviest build). Half the delta, half the step.
		["limb", 0.156 * w * belly, 0.140 * w * belly, 0.142, 0.302,
			dep + 0.055, 0.0, 1],
		# M18: this ball's front stood 5.9 mm proud of the abdomen barrel at the
		# centreline and crossed BACK inside it at |x| 0.115 — a near-tangential
		# crossing between a 22-sided limb and a 26-segment ball, which facets
		# into the wavy horizontal ridge that read as a second tube across the
		# shirt. Solved to sit 1 mm inside at EVERY girth now, not just at 1.0.
		["ball", Vector3(0, 0.245, -ab_r + 0.001 + wst_d * 0.5),
			Vector3(0.268 * w * belly, 0.215, wst_d), 1],
		["limb", 0.140 * w * belly, 0.150 * w, 0.298, 0.438, dep + 0.03, 0.0, 1],
		["limb", 0.150 * w, 0.150 * w, 0.412, 0.552, dep, 0.0, 1],
		# THE CLIFF (M20). The body's own front silhouette stepped 30.6 mm
		# BACKWARD across y = 0.552 on Book, 46.0 on a cop and 65.1 at the
		# heaviest build: above the barrel top the frontmost thing was the
		# trapezius cone, which is far aft because a trapezius is a BACK muscle.
		# Every wardrobe piece whose top edge crossed that line floated by
		# exactly the step — tie knot +36.3, V-neck accent +46.3, hi-vis front
		# panels +40.8, the back reflective band +57.7, apron straps +42.3. This
		# clavicle/upper-pec mass carries the front over the gap, so all of them
		# close at once instead of being nudged one at a time.
		# It is a tapered LIMB, not a ball, and it replaces the collar cone
		# outright: a limb's front is LINEAR in y, so the chest can walk up to
		# the neck root without a second step, and one cone from sternum to
		# collar is one surface instead of two that cross. Its radii are solved
		# so the front leaves the barrel 6 mm proud at y 0.540 and arrives at
		# z −0.052 at 0.625 — 2 mm in front of the neck — at EVERY build/girth.
		["limb", 0.150 * w - 0.012 / dep, 0.034 / dep, 0.540, 0.625,
			dep, -0.0180, 1],
		# pec swell forward, scapula plane aft — the side view lives or dies here
		["ball", Vector3(0, 0.478, -chest_f - 0.012 + pec_d * 0.5),
			Vector3(0.258 * w, 0.145, pec_d), 1],
		# the scapula plane had the same girth bug as the pec: fixed depth
		# against a barrel that moves. Solved to sit 1 mm proud at every girth.
		["ball", Vector3(0, 0.450, 0.150 * w * dep + 0.001 - 0.0919 * dep),
			Vector3(0.262 * w, 0.235, 0.1838 * dep), 1],
		# the swept shoulder girdle (see below). Declared as a MASS, not just as
		# geometry, so `_surface`/`_lay` can mount epaulets, a shoulder mic and a
		# vest strap on the real shoulder — out past |x| 0.13 the old mass list
		# described NOTHING, so every piece out there was laid against z = 0.
		_girdle_params(w, 1.0 + (g - 1.0) * 0.55),
	]


# ===================== THE SHOULDER GIRDLE (M21 — D-002/D-027) ===============
## Two agents in a row wrote the same sentence: this needs ONE SWEPT GIRDLE, not
## a trapezius ball plus two deltoid balls. They were right, and the reason is
## the same one that killed the muzzle patch in D-024 — two smooth convex
## surfaces that cross will be TANGENTIAL somewhere along the crossing curve, and
## a tangential crossing between a 26-segment ball and a 20-segment ball is the
## stipple in D-002 and the hard crease in D-027. No amount of resizing removes
## it; only removing the crossing does.
##
## So the trapezius, both acromions and both deltoids are now ONE surface swept
## along X: a ring in the (y, z) plane whose centre and radii vary from the
## trapezius section at the midline to the deltoid section at the shoulder joint,
## then close on an ogive that ends exactly at the old ball's outer edge (so the
## chest-span number does not jump). The only crossing left is girdle-to-sleeve,
## and that one is STEEP — a near-vertical tube through a surface whose normal
## there points down and outboard — which is a clean line, and it lands where a
## real sleeve seam lands.
##
## The centre section is deliberately IDENTICAL to the ball it replaces
## (yc −0.049, zc +0.020, half 0.103 × 0.112) so nothing else on the torso had to
## move and D-022's "pushed aft so the front is decisively buried" holds.
const GIRD_RY0 := 0.103
const GIRD_RZ0 := 0.112
const GIRD_YC0 := -0.049
const GIRD_ZC0 := 0.020
const GIRD_RY1 := 0.050
const GIRD_RZ1 := 0.070
const GIRD_YC1 := -0.019
const GIRD_ZC1 := 0.002
const DELT_R := 0.062       # deltoid reach past the joint; sets the chest span

static func _girdle_params(w: float, lg: float) -> Array:
	var f := 1.0 + (lg - 1.0) * 0.60          # heavier build, thicker shoulder
	var xs := SHOULDER_X * w
	var xe := xs + DELT_R * f
	return ["gird", xe, xs / xe, GIRD_RY0, GIRD_RZ0, GIRD_YC0, GIRD_ZC0,
		GIRD_RY1 * f, GIRD_RZ1 * f, GIRD_YC1, GIRD_ZC1, COLLAR_PIVOT.y, 1]


static func _gird_ring(m: Array, a: float) -> Array:
	var asx := float(m[2])
	if a <= asx:
		var t := pow(a / maxf(asx, 0.0001), 1.5)
		return [lerpf(float(m[3]), float(m[7]), t), lerpf(float(m[4]), float(m[8]), t),
			lerpf(float(m[5]), float(m[9]), t), lerpf(float(m[6]), float(m[10]), t)]
	var u := (a - asx) / maxf(1.0 - asx, 0.0001)
	var k := sqrt(maxf(1.0 - u * u, 0.0))
	return [float(m[7]) * k, float(m[8]) * k, float(m[9]), float(m[10])]


static var _gird_cache: Dictionary = {}
const GIRD_STATIONS := 15      # per half; mirrored
const GIRD_SEGS := 18

## One closed swept shell, smooth all the way across. WINDING: verified against
## `mesh_kit.round_limb`, which has rendered correctly since M10 — Godot's front
## face here is the one whose (b−a)×(c−a) points INWARD (D-021's law: primitive
## winding is checked against a known-good reference, never assumed).
static func _girdle_mesh(m: Array) -> ArrayMesh:
	var key := "gd_%.4f_%.4f_%.4f_%.4f" % [float(m[1]), float(m[2]), float(m[7]),
		float(m[8])]
	if _gird_cache.has(key):
		return _gird_cache[key]
	var xe := float(m[1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := GIRD_STATIONS * 2 + 1
	var pos: Array[Vector3] = []
	pos.resize(n * GIRD_SEGS)
	for i in n:
		# stations crowd toward the tips so the ogive stays round
		var s := float(i - GIRD_STATIONS) / float(GIRD_STATIONS)
		var a := pow(absf(s), 0.80)
		var r := _gird_ring(m, minf(a, 0.985))
		var x := signf(s) * a * xe
		for j in GIRD_SEGS:
			var ph := TAU * float(j) / float(GIRD_SEGS)
			pos[i * GIRD_SEGS + j] = Vector3(x,
				float(r[2]) + float(r[0]) * cos(ph),
				float(r[3]) + float(r[1]) * sin(ph))
	for i in n - 1:
		for j in GIRD_SEGS:
			var j2 := (j + 1) % GIRD_SEGS
			var a0 := i * GIRD_SEGS + j
			var b0 := i * GIRD_SEGS + j2
			var c0 := (i + 1) * GIRD_SEGS + j
			var d0 := (i + 1) * GIRD_SEGS + j2
			_t3(st, pos[a0], pos[c0], pos[d0])
			_t3(st, pos[a0], pos[d0], pos[b0])
	var lo := Vector3(-xe, float(m[9]), float(m[10]))
	var hi := Vector3(xe, float(m[9]), float(m[10]))
	var last := (n - 1) * GIRD_SEGS
	for j in GIRD_SEGS:
		var j2 := (j + 1) % GIRD_SEGS
		_t3(st, lo, pos[j], pos[j2])
		_t3(st, hi, pos[last + j2], pos[last + j])
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	_gird_cache[key] = mesh
	return mesh


static func _t3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## The skull, in head space. Entry 0 is the cranium ellipsoid kept as a pure
## REFERENCE (the hairline ring derives its radius from it); it is never drawn
## and never evaluated. Entry 1 is the head shell itself, so eyebrows, the
## hairline and facial hair are laid on the surface people actually see.
static func _face_masses(cfg: Dictionary) -> Array:
	var p := _face_params(cfg)
	return [
		["ref", CRAN_C, Vector3(CRAN_H.x * 2.0, CRAN_H.y * 2.0, CRAN_H.z * 2.0), 0],
		["muzz", Vector3(p[0], p[1], p[2]), p[3], 0],
	]


## Face shape knobs, QUANTISED. The head is one baked mesh; quantising here is
## what lets a crowd of sixteen share a handful of cached meshes instead of
## baking sixteen. The same rounded numbers feed `_surface`, so the evaluator
## and the geometry can never disagree.
static func _face_params(cfg: Dictionary) -> Array:
	var jaw := snappedf(float(cfg.get("jaw", 1.0)), 0.06)
	var nose := snappedf(float(cfg.get("nose", 1.0)), 0.06)
	var brow := snappedf(float(cfg.get("brow", 1.0)), 0.10)
	var asym := snappedf(float(cfg.get("asym", 0.0)), 0.50)
	var w := int(cfg.get("whiskers", Whiskers.CLEAN))
	var stub := 1.0 if (w == Whiskers.STUBBLE or w == Whiskers.FULL) else 0.0
	return [jaw, nose, brow, asym, stub]


# ======================= THE HEAD SHELL (M20 — D-001) ========================
## D-001: "the mid-face reads as a snout past 4x zoom". Measured on the M19
## head, inside the mid-face window (y 0.030–0.150, |x| ≤ 0.055): FIFTEEN
## separate primitives owned visible surface and 997 of 26,630 sample edges
## were owner changes. Every one of those is a crossing curve between two
## convex masses, and a face assembled from crossing curves is a muzzle. That
## is a topology fact, not a tuning one.
##
## So: ONE closed smooth surface is now the whole head, and the nose, alae,
## nostrils, philtrum, both lips, the mouth seam, the mentolabial sulcus, the
## chin, the brow, the orbits, the cheekbones and the jaw angle are all
## MODULATIONS on that single sheet.
##
## Why the whole head and not only the muzzle (this was tried first and
## measured): a muzzle patch has to end somewhere, and wherever it ends it
## crosses the cranium. At the crossing the cranium is flaring at dR/dy = +0.70
## while the patch is diving inward — measured normal step 30.7° at the
## mid-line, 54.7° on the cheek, 41.5° at the temple. There is no placement of
## that ring that is not a visible ledge, and burying the rim deeper only moves
## it. One surface has no crossing at all.
##
## The base is the SMOOTH union of the same two ellipsoids the factory always
## used — a hard max between cranium and jaw is itself a crease ring straight
## across the cheekbones. The mid-sagittal relief is SOLVED from an
## anthropometric target profile rather than dialled: nasion, dorsum, tip,
## subnasale, philtrum, both vermilions, stomion, sulcus, pogonion.
const HEAD_AXIS_Z := -0.002
const CRAN_C := Vector3(0.0, 0.150, 0.014)
# M20: cranium half-height 0.084 -> 0.1018. The quality bar wants total height
# / head height in 7.0–7.8 and every hatted character measured 8.138 (the
# ratio is scale-invariant, so it failed for the whole population). Solving
# (1.54 + T) / (T - 0.016) = 7.6 gives a crown at T = 0.2518, i.e. +17.8 mm.
# Only the VERTICAL radius grows, so the face's own width and its frontal
# profile move by under a millimetre — nothing else on the head had to move.
const CRAN_H := Vector3(0.077, 0.1018, 0.098)
const JAW_C := Vector3(0.0, 0.074, -0.006)
# ... and the mandible was 0.134*jaw wide against a 0.154 skull — a bigonial
# ratio of 0.955 where a human is ~0.78. That slab is half of why the lower
# face read as a muzzle. 0.120*jaw -> 0.86 on Book.
const JAW_H := Vector3(0.0530, 0.058, 0.071)
const HEAD_SMAX := 0.0075
# ================= D-029, MEASURED — THE MESH COULD NOT SEE THE NOSE =========
# "No nostrils, no alar crease, no philtrum" has survived three cycles of
# re-tuning `_face_relief`, and the reason is not the relief. It is SAMPLING.
# At 28 uniform segments the ring step is TAU/28 = 0.2244 rad, so on a skull of
# radius 0.075 the first vertex off the mid-line sits at x = 16.7 mm. The
# nostril bump is centred at |x| = 9.0 mm with a 4.8 mm half-width; the philtrum
# ridges at 7.4 ± 4.0; the alar crease at 12.6 ± 8.2. Every one of them lives
# ENTIRELY BETWEEN the x = 0 column and the x = 16.7 mm column. They have been
# in the code, correct, and unrenderable the whole time — which is also why the
# mid-face reads as one smooth forward mass: a nose sampled twice IS a muzzle.
#
# 48 segments on a WARPED distribution (|s|^1.7) rather than 96 uniform ones:
# the front columns land at x = 0, 1.1, 3.6, 7.2, 11.7, 17.0, 23.0 mm — two
# samples inside the nostril and three across the ala — while the back of the
# cranium keeps a 0.22 rad step, exactly what it has now. 4,224 triangles a head
# against 2,464, and heads are cached on the quantised shape knobs, so a crowd
# of sixteen still shares a handful of meshes.
const HEAD_SEGS := 48
const HEAD_WARP := 1.7
const HEAD_YB := 0.0160
const HEAD_YT := 0.2518

static var _head_cache: Dictionary = {}
# ring heights: dense through the mouth and nose, dense again at both poles so
# the crown is a dome and not a cone
static var _head_ys := PackedFloat32Array([
	0.0175, 0.0205, 0.0248, 0.0300, 0.0358, 0.0416, 0.0470, 0.0522,
	0.0572, 0.0618, 0.0660, 0.0700, 0.0736, 0.0770, 0.0800, 0.0828,
	0.0855, 0.0880, 0.0902, 0.0922, 0.0942, 0.0962, 0.0985, 0.1010,
	0.1040, 0.1075, 0.1115, 0.1160, 0.1210, 0.1265, 0.1325, 0.1390,
	0.1465, 0.1545, 0.1630, 0.1725, 0.1830, 0.1940, 0.2050, 0.2155,
	0.2250, 0.2330, 0.2400, 0.2455, 0.2500])
# how far out from the mid-line the sagittal relief carries, per height
static var _face_carry := PackedVector2Array([
	Vector2(0.0160, 0.0180), Vector2(0.0330, 0.0240), Vector2(0.0410, 0.0260),
	Vector2(0.0530, 0.0190), Vector2(0.0668, 0.0290), Vector2(0.0800, 0.0280),
	Vector2(0.0880, 0.0165), Vector2(0.0920, 0.0125), Vector2(0.0955, 0.0105),
	Vector2(0.1040, 0.0086), Vector2(0.1220, 0.0076), Vector2(0.1490, 0.0072)])
# THE TARGET: the SMOOTH absolute mid-sagittal z. The three local grooves
# (philtrum, stomion, mentolabial sulcus) are carved BELOW these numbers, so
# the target line runs straight through where the lips would meet.
# Ricketts E-line check on these numbers: upper lip 4.8 mm behind the
# tip-to-pogonion line, lower lip 0.3 mm in front — a normal adult profile.
# The M19 head had NO bridge (a rectangular slab flush with the forehead for
# 37 mm), a 0.7 mm lower lip and a chin 15 mm BEHIND the lips.
static var _face_target := PackedVector2Array([
	Vector2(0.0250, -0.0640), Vector2(0.0300, -0.0748), Vector2(0.0365, -0.0812),
	Vector2(0.0410, -0.0828),
	Vector2(0.0455, -0.0836), Vector2(0.0495, -0.0846), Vector2(0.0530, -0.0858),
	Vector2(0.0562, -0.0878), Vector2(0.0590, -0.0886), Vector2(0.0618, -0.0884),
	Vector2(0.0645, -0.0880), Vector2(0.0668, -0.0884), Vector2(0.0690, -0.0886),
	Vector2(0.0715, -0.0884), Vector2(0.0742, -0.0888), Vector2(0.0768, -0.0880),
	Vector2(0.0795, -0.0868), Vector2(0.0825, -0.0862), Vector2(0.0855, -0.0854),
	Vector2(0.0880, -0.0854), Vector2(0.0900, -0.0905), Vector2(0.0925, -0.0970),
	Vector2(0.0955, -0.1016), Vector2(0.0985, -0.1030), Vector2(0.1010, -0.1014),
	Vector2(0.1060, -0.0990), Vector2(0.1140, -0.0956), Vector2(0.1220, -0.0924),
	Vector2(0.1300, -0.0894), Vector2(0.1380, -0.0872), Vector2(0.1440, -0.0850),
	Vector2(0.1500, -0.0846)])
static var _face_spine := PackedVector2Array()


static func _bmp(t: float) -> float:
	if absf(t) >= 1.0:
		return 0.0
	var s := 1.0 - t * t
	return s * s


static func _sst(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func _kn(tbl: PackedVector2Array, t: float) -> float:
	var n := tbl.size()
	if t <= tbl[0].x:
		return tbl[0].y
	if t >= tbl[n - 1].x:
		return tbl[n - 1].y
	for i in n - 1:
		var b := tbl[i + 1]
		if t <= b.x:
			var a := tbl[i]
			return a.y + (b.y - a.y) * _sst((t - a.x) / (b.x - a.x))
	return tbl[n - 1].y


## Farthest exit of the ray (0, HEAD_AXIS_Z) + t*(sx, sz) from one ellipse.
static func _ell_exit(cz: float, ax: float, az: float, sx: float,
		sz: float) -> float:
	var oz := HEAD_AXIS_Z - cz
	var a := (sx / ax) * (sx / ax) + (sz / az) * (sz / az)
	var b := 2.0 * oz * sz / (az * az)
	var c := (oz / az) * (oz / az) - 1.0
	var d := b * b - 4.0 * a * c
	if d <= 0.0:
		return 0.0
	return maxf(0.0, (-b + sqrt(d)) / (2.0 * a))


## Radius of the smooth cranium+jaw union at (theta, y). A hard max here is a
## crease: measured, the two fronts cross within 0.6 mm of each other around
## y 0.105, which put a ledge across both cheekbones on every character.
static func _head_r0(theta: float, y: float, jaw: float) -> float:
	var sx := sin(theta)
	var sz := -cos(theta)
	var ra := 0.0
	var rb := 0.0
	var q := 1.0 - ((y - CRAN_C.y) / CRAN_H.y) * ((y - CRAN_C.y) / CRAN_H.y)
	if q > 0.0:
		var s := sqrt(q)
		ra = _ell_exit(CRAN_C.z, CRAN_H.x * s, CRAN_H.z * s, sx, sz)
	q = 1.0 - ((y - JAW_C.y) / JAW_H.y) * ((y - JAW_C.y) / JAW_H.y)
	if q > 0.0:
		var s := sqrt(q)
		rb = _ell_exit(JAW_C.z, JAW_H.x * jaw * s, JAW_H.z * s, sx, sz)
	if ra <= 0.0:
		return rb
	if rb <= 0.0:
		return ra
	var h := maxf(HEAD_SMAX - absf(ra - rb), 0.0) / HEAD_SMAX
	return maxf(ra, rb) + h * h * HEAD_SMAX * 0.25


## The three purely-subtractive mid-line grooves, kept separate so the spine
## can be solved against the target without double-counting them.
static func _face_grooves(x: float, y: float, asym: float) -> float:
	var g := -0.0017 * _bmp(x / 0.0058) * _bmp((y - 0.0818) / 0.0062)
	var ys := 0.0668 - 0.0017 * (x / 0.0300) * (x / 0.0300) \
		+ 0.0016 * asym * (x / 0.0300)
	g -= 0.0052 * _bmp(x / 0.0310) * _bmp((y - ys) / 0.0042)
	g -= 0.0022 * _bmp(x / 0.0330) * _bmp((y - 0.0502) / 0.0074)
	return g


static func _spine() -> PackedVector2Array:
	if _face_spine.is_empty():
		var out := PackedVector2Array()
		for t: Vector2 in _face_target:
			var zb := HEAD_AXIS_Z - _head_r0(0.0, t.x, 1.0)
			out.append(Vector2(t.x, zb - t.y))
		_face_spine = out
	return _face_spine


## Outward push, in metres, at (theta, x, y). Zero everywhere the face is not.
static func _face_relief(theta: float, x: float, y: float, jaw: float,
		nose: float, brow: float, asym: float) -> float:
	var ax := absf(x)
	var at := absf(theta)
	var fw := _sst((cos(theta) + 0.10) / 0.40)
	var d := _kn(_spine(), y) * _bmp(ax / (_kn(_face_carry, y) * 1.55)) * fw
	d += 0.0098 * _bmp((ax - 0.0126 * nose) / (0.0082 * nose)) \
		* _bmp((y - 0.0936) / 0.0126) * fw                    # alae
	# M21: now that the ring actually samples this window (see HEAD_SEGS), the
	# nostril can be a nostril — 3.4 mm of dimple was sized to be safe on a mesh
	# that never drew it.
	d -= 0.0052 * _bmp((ax - 0.0092 * nose) / (0.0050 * nose)) \
		* _bmp((y - 0.0893) / 0.0058) * fw                    # nostrils
	d += 0.0011 * _bmp((ax - 0.0074) / 0.0040) \
		* _bmp((y - 0.0818) / 0.0064) * fw                    # philtrum ridges
	d += 0.0017 * _bmp((ax - 0.0090) / 0.0074) \
		* _bmp((y - 0.0760) / 0.0050) * fw                    # cupid's bow
	var fx := 0.0225 + 0.0135 * (0.0900 - y) / 0.0260
	d -= 0.0030 * _bmp((ax - fx) / 0.0072) \
		* _bmp((y - 0.0772) / 0.0168) * fw                    # nasolabial fold (M23: 1.7 -> 3.0 mm)
	# M23 LIP CROWNS. The target profile ran "straight through where the lips
	# would meet" and gave them 0.2-0.6 mm of volume; at `face` that is a line
	# on a smooth surface. Real lips stand 3-5 mm proud. Same mouth line (ys)
	# the tint rows use, so colour and relief agree.
	var ysl := 0.0668 - 0.0017 * (x / 0.0300) * (x / 0.0300) + 0.0016 * asym * (x / 0.0300)
	d += 0.0028 * _bmp(x / 0.0262) * _bmp((y - (ysl + 0.0072)) / 0.0070) * fw   # upper lip
	d += 0.0038 * _bmp(x / 0.0248) * _bmp((y - (ysl - 0.0084)) / 0.0078) * fw   # lower lip
	d -= 0.0026 * _bmp((ax - 0.0195 * nose) / (0.0080 * nose)) \
		* _bmp((y - 0.0995) / 0.0130) * fw                    # supra-alar crease
	d += _face_grooves(x, y, asym) * fw
	d += 0.0065 * brow * _bmp((ax - 0.0300) / 0.0300) \
		* _bmp((y - 0.1455) / 0.0150) * fw                    # supraorbital ridge (M23: 4.2 -> 6.5 mm)
	d += 0.0045 * brow * _bmp(ax / 0.0190) \
		* _bmp((y - 0.1490) / 0.0150) * fw                    # glabella (3.2 -> 4.5)
	d -= 0.0075 * _bmp((ax - 0.0420) / 0.0330) \
		* _bmp((y - 0.1285) / 0.0190) * fw                    # orbit (M23: 3.2 -> 7.5 mm — a socket, not a dip)
	d += 0.0055 * _bmp((at - 0.74) / 0.52) * _bmp((y - 0.1010) / 0.0280)   # cheekbone (3.0 -> 5.5)
	d += 0.0026 * _bmp((at - 1.62) / 0.72) * _bmp((y - 0.0820) / 0.0420) * jaw
	d -= 0.0024 * _bmp((at - 1.00) / 0.42) * _bmp((y - 0.1640) / 0.0320)
	# THE JAW BLOCK. Left to the bare ellipsoid the mandible tapers to a POINT
	# under the chin, which read as a weasel snout from `portrait` — a real
	# mandible is a horseshoe with a broad chin, so the bottom rings are pushed
	# out everywhere EXCEPT the mid-line (which the solved spine owns) and the
	# nape. This is also what closes D-004's cousin: nothing here is a ball.
	d += 0.0035 * _bmp((at - 1.28) / 1.06) * _bmp((y - 0.0430) / 0.0420)
	return d


## Vertex TINT — a multiplier on the skin, never an absolute colour, so one
## cached mesh serves all eight skin tones. D-003 wanted the mouth to register
## at `face` without going back to being a floating dark bar: it is a 4.2 mm
## groove with 3–4 mm of lip crown either side, and the colour only confirms
## what the geometry already says.
static func _face_tint(x: float, y: float, theta: float, asym: float,
		stub: float) -> Color:
	var ys := 0.0668 - 0.0017 * (x / 0.0300) * (x / 0.0300) \
		+ 0.0016 * asym * (x / 0.0300)
	var fw := _sst((cos(theta) + 0.10) / 0.40)
	var t := Color(1, 1, 1)
	if stub > 0.0:
		t = t.lerp(Color(0.80, 0.78, 0.77), stub * _bmp((y - 0.0560) / 0.0560)
			* _sst((cos(theta) + 0.30) / 0.60))
	t = t.lerp(Color(1.06, 0.64, 0.61),
		fw * _bmp(x / 0.0272) * _bmp((y - (ys + 0.0072)) / 0.0098))
	t = t.lerp(Color(1.12, 0.72, 0.68),
		fw * _bmp(x / 0.0258) * _bmp((y - (ys - 0.0084)) / 0.0106))
	t = t.lerp(Color(0.24, 0.17, 0.16),
		fw * _bmp(x / 0.0286) * _bmp((y - ys) / 0.0046))
	t = t.lerp(Color(0.16, 0.12, 0.11),
		fw * _bmp((absf(x) - 0.0090) / 0.0052) * _bmp((y - 0.0893) / 0.0058))
	return t


## Front z of the shell at (x, y), or INF if that column misses the head.
## Solved by fixed point: the radius depends on theta and theta on the radius,
## but the map is a strong contraction near the face and settles in four steps.
static func _head_front(x: float, y: float, jaw: float, nose: float,
		brow: float, asym: float) -> float:
	if y < HEAD_YB or y > HEAD_YT:
		return INF
	var th := 0.0
	var r := 0.0
	for _i in 5:
		r = _head_r0(th, y, jaw)
		r += _face_relief(th, r * sin(th), y, jaw, nose, brow, asym)
		if r <= 0.0001:
			return INF
		var s := x / r
		if absf(s) > 0.999:
			return INF
		th = asin(s)
	return HEAD_AXIS_Z - r * cos(th)


## Ring angle for column `j`: 0 = dead front, ±PI = dead back, crowded toward
## the front so the mid-face is sampled finely enough to HAVE a mid-face.
static func _head_theta(j: int) -> float:
	var u := float(j) / float(HEAD_SEGS)
	var s := u * 2.0 if u <= 0.5 else (u - 1.0) * 2.0
	return PI * signf(s) * pow(absf(s), HEAD_WARP)


## One head, one mesh, cached on the quantised shape knobs.
static func _head_mesh(jaw: float, nose: float, brow: float, asym: float,
		stub: float) -> ArrayMesh:
	var key := "hd_%.2f_%.2f_%.2f_%.2f_%.0f" % [jaw, nose, brow, asym, stub]
	if _head_cache.has(key):
		return _head_cache[key]
	var nring := _head_ys.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var pos: Array[Vector3] = []
	var col: Array[Color] = []
	pos.resize(nring * HEAD_SEGS)
	col.resize(nring * HEAD_SEGS)
	for i in nring:
		var y := _head_ys[i]
		for j in HEAD_SEGS:
			var th := _head_theta(j)
			var r0 := _head_r0(th, y, jaw)
			var x0 := r0 * sin(th)
			var r := r0 + _face_relief(th, x0, y, jaw, nose, brow, asym)
			pos[i * HEAD_SEGS + j] = Vector3(r * sin(th), y,
				HEAD_AXIS_Z - r * cos(th))
			col[i * HEAD_SEGS + j] = _face_tint(x0, y, th, asym, stub)
	# WINDING (D-021's law — verified against `taper`, which has rendered
	# correctly since M10): Godot's front face here is the one whose
	# (b-a)x(c-a) points INWARD, so the ring quad is wound a -> d -> c and
	# a -> b -> d, not the other way about. A harness re-measured the baked
	# normals against the outward radial and got 100% outward.
	for i in nring - 1:
		for j in HEAD_SEGS:
			var j2 := (j + 1) % HEAD_SEGS
			var a := i * HEAD_SEGS + j
			var b := i * HEAD_SEGS + j2
			var c := (i + 1) * HEAD_SEGS + j
			var d := (i + 1) * HEAD_SEGS + j2
			_ctri(st, pos, col, a, d, c)
			_ctri(st, pos, col, a, b, d)
	var bot := Vector3(0, HEAD_YB - 0.0012, JAW_C.z)
	var top := Vector3(0, HEAD_YT + 0.0006, CRAN_C.z)
	var lastr := (nring - 1) * HEAD_SEGS
	for j in HEAD_SEGS:
		var j2 := (j + 1) % HEAD_SEGS
		_ptri(st, bot, Color(1, 1, 1), pos, col, j2, j)
		_ptri(st, top, Color(1, 1, 1), pos, col, lastr + j, lastr + j2)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_head_cache[key] = m
	return m


static func _ctri(st: SurfaceTool, pos: Array[Vector3], col: Array[Color],
		a: int, b: int, c: int) -> void:
	st.set_color(col[a]); st.add_vertex(pos[a])
	st.set_color(col[b]); st.add_vertex(pos[b])
	st.set_color(col[c]); st.add_vertex(pos[c])


static func _ptri(st: SurfaceTool, p: Vector3, pc: Color, pos: Array[Vector3],
		col: Array[Color], a: int, b: int) -> void:
	st.set_color(pc); st.add_vertex(p)
	st.set_color(col[a]); st.add_vertex(pos[a])
	st.set_color(col[b]); st.add_vertex(pos[b])


## Frontmost (`front`) or rearmost z of the union of `masses` at (x, y).
## Returns 0.0 where no mass covers the point — callers only ask about points
## that are on the body.
static func _surface(masses: Array, x: float, y: float, front: bool) -> float:
	var best := 0.0
	for m: Array in masses:
		var z := 0.0
		if str(m[0]) == "ref":
			continue
		elif str(m[0]) == "muzz":
			if not front:
				continue
			var p: Vector3 = m[1]
			z = _head_front(x, y, p.x, p.y, p.z, float(m[2]))
			if is_inf(z):
				continue
		elif str(m[0]) == "gird":
			# the swept shoulder girdle, evaluated in COLLAR space
			var ax := absf(x)
			if ax >= float(m[1]):
				continue
			var r := _gird_ring(m, ax / float(m[1]))
			if float(r[0]) <= 0.0002:
				continue
			var gy := (y - float(m[11]) - float(r[2])) / float(r[0])
			if absf(gy) >= 1.0:
				continue
			var hg := float(r[1]) * sqrt(1.0 - gy * gy)
			z = float(r[3]) + (-hg if front else hg)
		elif str(m[0]) == "limb":
			var y0 := float(m[3])
			var y1 := float(m[4])
			if y < y0 or y > y1:
				continue
			var r := lerpf(float(m[1]), float(m[2]),
				(y - y0) / maxf(y1 - y0, 0.0001))
			if absf(x) >= r:
				continue
			var h := float(m[5]) * r * sqrt(1.0 - (x / r) * (x / r))
			z = float(m[6]) + (-h if front else h)
		else:
			var c: Vector3 = m[1]
			var d: Vector3 = m[2]
			var u := (x - c.x) / maxf(d.x * 0.5, 0.0001)
			var v := (y - c.y) / maxf(d.y * 0.5, 0.0001)
			var q := 1.0 - u * u - v * v
			if q <= 0.0:
				continue
			var hb := d.z * 0.5 * sqrt(q)
			z = c.z + (-hb if front else hb)
		best = minf(best, z) if front else maxf(best, z)
	return best


## Lay a flat piece ON the curved body at (x, y): the surface point pushed
## `proud` metres along the outward normal, plus the yaw and pitch that make the
## piece parallel to the surface there. Returns [position, rotation].
##
## Node3D composes Euler as Y*X*Z, so a piece's outward face (local -Z) ends up
## at (-cos(pitch)sin(yaw), sin(pitch), -cos(pitch)cos(yaw)) — matched against
## the surface gradient below. Getting this sign wrong is not cosmetic: the M16
## hi-vis vest panels were yawed the WRONG way, so both front panels flared
## forward off the chest instead of wrapping it.
static func _lay(masses: Array, x: float, y: float, proud: float,
		front := true) -> Array:
	const D := 0.006
	var z := _surface(masses, x, y, front)
	var zx := (_surface(masses, x + D, y, front)
		- _surface(masses, x - D, y, front)) / (2.0 * D)
	var zy := (_surface(masses, x, y + D, front)
		- _surface(masses, x, y - D, front)) / (2.0 * D)
	if front:
		return [Vector3(x, y, z - proud), Vector3(atan(zy), -atan(zx), 0.0)]
	return [Vector3(x, y, z + proud), Vector3(-atan(zy), PI - atan(zx), 0.0)]


## A flat wardrobe piece, mounted. `proud` is how far the piece's CENTRE stands
## off the surface (default: a quarter of its thickness, so the back half is
## buried in the cloth and no edge can lift). Wide pieces sink by their own sag
## so their corners land on the body too.
static func _panel(parent: Node3D, masses: Array, x: float, y: float,
		size: Vector3, top: Vector2, mat: Material,
		front := true, vis_end := 0.0, proud := -1.0,
		y_offset := 0.0, roll := 0.0) -> void:
	var p := proud if proud > -0.5 else size.z * 0.22
	# M18: sag is measured over the piece's WIDEST edge, not its bottom one. A
	# collar point is 0.026 at the point and 0.048 at the neck; sagging it by the
	# 0.026 figure left the wide end's outer corner standing off the chest — the
	# "one collar point still shows a proud edge" complaint.
	#
	# M21: and it was only ever measured ACROSS the piece. `_lay` tilts a panel to
	# the surface's slope at its centre, which kills the linear term in y — but
	# not the CURVATURE, and the chest's front profile bends hard (it swings from
	# −0.37 to +0.42 of slope across the pec). Every panel that survived the width
	# fix was still failing on its top or bottom edge: the placket at 7.6 mm, the
	# apron at 13.0, the jersey back band at 8.8, the hi-vis back band at 18.1.
	# `_bow` measures the residual AFTER the tilt, which is the honest number, and
	# sinking by it is what finally puts these under the 5 mm bar at every corner
	# of the roll instead of only in the middle of it.
	# The 0.55 was M18's hedge against a piece sinking out of sight. It is now a
	# full compensation with an explicit FLOOR instead: sink by whatever the
	# surface actually does, but never so far that the piece's outer face stops
	# standing 1.5 mm proud at its mount point. A hedge that leaves a corner
	# 18 mm in the air is not a hedge, it is the defect.
	p -= _sag(masses, x, y, maxf(size.x, top.x) * 0.42, front) * 0.90
	p -= _bow(masses, x, y, size.y * 0.5, front) * 0.85
	p = maxf(p, 0.0015 - size.z * 0.5)
	var l := _lay(masses, x, y, p, front)
	var pos: Vector3 = l[0]
	var rot: Vector3 = l[1]
	_put(parent, KIT.taper(size, top), pos + Vector3(0, y_offset, 0), mat,
		Vector3.ONE, Vector3(rot.x, rot.y, roll), vis_end)


## A ROUNDED feature laid on the curved body — same surface evaluation as
## `_panel`, but a ball has no corners to lift, so a CHAIN of these draws a line
## (an eyebrow, a hairline, a yoke seam) that follows the skull or the barrel
## instead of chording across it.
##
## This exists because M17's face put its dark features on as single wide
## ellipsoids and MEASURED (M18) they were not on the face at all: the eyebrow's
## outer rim stood 37.9 mm off the temple and the hair fringe's corners 21 mm —
## which is the black brick and the two black slabs in the `face` shot. A chain
## of five short laid balls lifts 7.6 mm at worst, and that is thickness, not a
## gap.
static func _lay_ball(parent: Node3D, masses: Array, x: float, y: float,
		dia: Vector3, mat: Material, proud: float, roll := 0.0,
		rings := 5, segs := 10, vis_end := 0.0, y_offset := 0.0,
		front := true) -> void:
	var l := _lay(masses, x, y, proud, front)
	var pos: Vector3 = l[0]
	var rot: Vector3 = l[1]
	_ball(parent, pos + Vector3(0, y_offset, 0), dia, mat,
		Vector3(rot.x, rot.y, roll), rings, segs, vis_end)


## Vertical BOW: how far the surface departs from its own tangent plane over a
## half-height. `_lay` already matches the slope at the mount point, so the
## linear term is subtracted out and what is left is pure curvature — the part
## no amount of tilting can follow.
static func _bow(masses: Array, x: float, y: float, half: float,
		front: bool) -> float:
	if half <= 0.001:
		return 0.0
	var c := _surface(masses, x, y, front)
	if absf(c) < 0.0001:
		return 0.0
	const D := 0.006
	var gy := (_surface(masses, x, y + D, front)
		- _surface(masses, x, y - D, front)) / (2.0 * D)
	var s := 0.0
	for e: float in [-half, half]:
		var v := _surface(masses, x, y + e, front)
		if absf(v) < 0.0001:
			continue
		s = maxf(s, absf(v - c - gy * e))
	return s


## How far the surface drops away from (x, y) over a half-width — the amount a
## rigid flat panel would otherwise hover at its own corners.
static func _sag(masses: Array, x: float, y: float, half: float,
		front: bool) -> float:
	if half <= 0.001:
		return 0.0
	var c := _surface(masses, x, y, front)
	if absf(c) < 0.0001:
		return 0.0
	var s := 0.0
	for e: float in [-half, half]:
		var v := _surface(masses, x + e, y, front)
		if absf(v) < 0.0001:
			continue
		s = maxf(s, absf(v - c))
	return s


# ------------------------------ legs -----------------------------------------
static func _build_legs(vis: Node3D, rig: Dictionary, cfg: Dictionary,
		lg: float) -> void:
	var pants := _m(cfg["pants"], 0.88)
	var skin := _skin(cfg["skin"], float(cfg.get("skin_rough", 0.72)))
	var shorts := bool(cfg.get("shorts", false))
	var shoe_style := int(cfg.get("shoe", Shoe.SNEAKER))
	var shoe := _m(cfg.get("shoe_color", BOOT), 0.62)
	var sole := _m(Color(0.11, 0.10, 0.10), 0.9)

	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var hip := Node3D.new()
		hip.position = Vector3(sx * HIP_PIVOT.x, HIP_PIVOT.y, HIP_PIVOT.z)
		vis.add_child(hip)
		# hip socket: the ball that stops a thigh from being a dowel in a hole.
		# M20 pulled it 14 mm inboard and 19 mm smaller so the pelvis barrel can
		# cover it — at 0.215 across sitting at x 0.112 its outer edge stood
		# 27.6 mm proud of the pelvis, which is a lobe, not a hip.
		_ball(hip, Vector3(-sx * 0.002, -0.020, 0.008),
			Vector3(0.170 * lg, 0.190, 0.180 * lg), pants, Vector3.ZERO, 9, 16)
		if shorts:
			_limb(hip, 0.086 * lg, 0.100 * lg, 0.26, Vector3(0, -0.13, 0), pants)
			_limb(hip, 0.072 * lg, 0.086 * lg, 0.05, Vector3(0, -0.283, 0),
				pants, Vector3(1.14, 1.0, 1.14))      # shorts hem flare
			_limb(hip, 0.070 * lg, 0.082 * lg, 0.16, Vector3(0, -0.36, 0), skin)
		else:
			_limb(hip, 0.078 * lg, 0.100 * lg, 0.44, Vector3(0, -0.22, 0), pants)

		var knee := Node3D.new()
		knee.position = KNEE_PIVOT
		hip.add_child(knee)
		var leg := skin if shorts else pants
		_ball(knee, Vector3(0, 0.005, -0.008),
			Vector3(0.150 * lg, 0.142, 0.150 * lg), leg, Vector3.ZERO, 8, 14)
		# calf belly high, hard taper to a real ankle
		_limb(knee, 0.086 * lg, 0.076 * lg, 0.17, Vector3(0, -0.085, 0.006), leg)
		_limb(knee, 0.047 * lg, 0.086 * lg, 0.28, Vector3(0, -0.31, 0.003), leg)
		_build_shoe(knee, shoe_style, shoe, sole, cfg)

		rig["hip_%d" % side] = hip
		rig["knee_%d" % side] = knee


## Ground is knee-local y = -0.47. A shoe is a sole plate, a rounded upper, a
## toe box and a heel — never a block. Boots add a shaft over the ankle.
static func _build_shoe(knee: Node3D, style: int, shoe: Material,
		sole: Material, cfg: Dictionary) -> void:
	var wid := 0.104
	var lon := 0.255
	var toe_z := -0.128
	match style:
		Shoe.BOOT:
			# D-081, measured: "a hard horizontal seam across both legs at
			# mid-calf, navy above and darker navy below, with no geometry
			# change at the line." There IS a geometry change — this shaft. Its
			# top ring was r 0.079 against a trouser that measures 0.0721·lg at
			# the same height, so 7 mm of boot stood outside the trouser and
			# `round_limb`'s flat top cap drew a hard ring right round both
			# calves. The shaft now comes IN under the cloth (0.068 against
			# 0.0721 at lg 1.0, and still under it at the slim corner) and only
			# emerges at y −0.39, where a trouser hem actually breaks over a boot.
			_limb(knee, 0.058, 0.064, 0.15, Vector3(0, -0.345, 0.004), shoe)
			_ball(knee, Vector3(0, -0.408, -0.008), Vector3(0.108, 0.09, 0.135), shoe)
			wid = 0.102; lon = 0.245; toe_z = -0.126
		Shoe.DRESS:
			_limb(knee, 0.052, 0.062, 0.09, Vector3(0, -0.405, 0.004), shoe)
			wid = 0.094; lon = 0.255; toe_z = -0.132
		Shoe.CLOG:
			_limb(knee, 0.052, 0.062, 0.09, Vector3(0, -0.405, 0.004), shoe)
			wid = 0.104; lon = 0.225; toe_z = -0.112
		_:
			_limb(knee, 0.056, 0.066, 0.10, Vector3(0, -0.40, 0.004), shoe)
			wid = 0.106; lon = 0.250; toe_z = -0.124
	var mid := -0.035
	# sole plate (bottom at exactly -0.470 so the figure stands ON the ground)
	_taper(knee, Vector3(wid, 0.024, lon), Vector2(wid * 0.96, lon * 0.97),
		Vector3(0, -0.458, mid), sole)
	# upper: narrower and shorter on top — an instep, not a shoebox
	_taper(knee, Vector3(wid * 0.96, 0.062, lon * 0.97),
		Vector2(wid * 0.80, lon * 0.72), Vector3(0, -0.415, mid), shoe,
		Vector3.ZERO, Vector2(0, 0.026))
	_ball(knee, Vector3(0, -0.436, toe_z), Vector3(wid * 0.90, 0.050, 0.072), shoe)
	# heel counter and (on boots) a stacked heel block
	_ball(knee, Vector3(0, -0.400, mid + lon * 0.44),
		Vector3(wid * 0.88, 0.078, 0.068), shoe)
	if style == Shoe.BOOT:
		_taper(knee, Vector3(wid * 0.78, 0.030, 0.085), Vector2(wid * 0.86, 0.09),
			Vector3(0, -0.455, mid + lon * 0.38), _m(Color(0.09, 0.07, 0.06), 0.8))
	if style == Shoe.SNEAKER:
		_taper(knee, Vector3(wid * 1.01, 0.016, lon * 0.99),
			Vector2(wid * 1.01, lon * 0.99), Vector3(0, -0.438, mid),
			_m(cfg.get("accent", Color(0.9, 0.9, 0.88)), 0.8))


# ------------------------------ torso ----------------------------------------
static func _build_torso(vis: Node3D, rig: Dictionary, cfg: Dictionary,
		w: float, g: float, masses: Array) -> Node3D:
	var pants := _m(cfg["pants"], 0.88)
	var shirt := _m(cfg["shirt"], 0.92)

	var torso := Node3D.new()
	torso.position = TORSO_PIVOT
	vis.add_child(torso)
	rig["torso"] = torso

	# The barrel, emitted straight from the declared masses. 16-sided limbs and
	# 16-segment balls: at 9 sides the front facet spanned 40 deg, which is what
	# made a chest photograph as a sheet of cardboard at 1 m.
	for m: Array in masses:
		var mat := pants if int(m[m.size() - 1]) == 0 else shirt
		if str(m[0]) == "gird":
			continue                       # emitted below, on the collar node
		elif str(m[0]) == "limb":
			var y0 := float(m[3])
			var y1 := float(m[4])
			_limb(torso, float(m[1]), float(m[2]), y1 - y0,
				Vector3(0, (y0 + y1) * 0.5, float(m[6])), mat,
				Vector3(1, 1, float(m[5])), Vector3.ZERO, 0.0, 22)
		else:
			_ball(torso, m[1], m[2], mat, Vector3.ZERO, 12, 26)

	# ---- THE SHOULDER GIRDLE (M21) — one swept surface from deltoid to deltoid.
	var collar := Node3D.new()
	collar.position = COLLAR_PIVOT
	torso.add_child(collar)
	rig["collar"] = collar
	for m: Array in masses:
		if str(m[0]) == "gird":
			_put(collar, _girdle_mesh(m), Vector3.ZERO, shirt, Vector3.ONE,
				Vector3.ZERO)
	# The trapezius BALL that stood here until M21 (0.372·w × 0.206 × 0.224,
	# centred −0.049 / +0.020) is gone: the girdle's own centre section is that
	# ellipsoid's cross-section exactly, so nothing else on the torso moved, but
	# the two arm caps are now the SAME SURFACE instead of two more balls
	# crossing it. That crossing was D-002's stipple and D-027's hard crease.
	# (the neck cone that used to live here is the clavicle limb declared in
	# `_torso_masses` — see THE CLIFF. Two cones from chest to neck crossed
	# each other; one carries the whole front.)

	var head := Node3D.new()
	head.position = HEAD_PIVOT
	collar.add_child(head)
	rig["head"] = head
	return torso


# ------------------------------ head -----------------------------------------
## ONE head shell (see the M20 block above) carrying nose, alae, nostrils,
## philtrum, both lips, the mouth seam, the sulcus, chin, brow, orbits,
## cheekbones and jaw angle as modulations — plus ears, eyes, hair and a hat.
static func _brow_strip(head: Node3D, face: Array, side: float, asym: float, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Vector3] = []
	for i in 21:
		var t := float(i) / 20.0
		var x := side * lerpf(0.020, 0.065, t)
		var y := 0.149 + 0.004 * sin(t * PI) - 0.004 * t + 0.0018 * asym * side
		var half := 0.0028 * pow(sin(PI * clampf(t, 0.025, 0.975)), 0.45)
		for edge in [-1.0, 1.0]:
			var yy: float = y + half * edge
			rows.append(Vector3(x, yy, _surface(face, x, yy, true) - 0.0012))
	for i in 20:
		var a := i * 2
		if side > 0:
			_t3(st, rows[a], rows[a + 3], rows[a + 1])
			_t3(st, rows[a], rows[a + 2], rows[a + 3])
		else:
			_t3(st, rows[a], rows[a + 1], rows[a + 3])
			_t3(st, rows[a], rows[a + 3], rows[a + 2])
	st.generate_normals()
	_put(head, st.commit(), Vector3.ZERO, material, Vector3.ONE, Vector3.ZERO)


static func _scalp_mesh(cfg: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	var params := _face_params(cfg)
	var style := int(cfg.get("hairdo", Hairdo.SHORT))
	var volume := 0.001
	if int(cfg.get("hat", Hat.NONE)) == Hat.NONE:
		if style == Hairdo.AFRO:
			volume = 0.018
		elif style == Hairdo.WAVY:
			volume = 0.009
		elif style != Hairdo.BUZZ:
			volume = 0.005
	for row in 25:
		for j in 64:
			var theta := TAU * float(j) / 64.0
			var front := (cos(theta) + 1.0) * 0.5
			var hairline := lerpf(0.096, 0.201, pow(front, 1.3))
			hairline += 0.005 * sin(theta * 3.0) * front
			var y := lerpf(hairline, 0.251, float(row) / 24.0)
			var r := _head_r0(theta, y, params[0])
			r += _face_relief(theta, r * sin(theta), y, params[0], params[1], params[2], params[3])
			r += 0.0018 + 0.0003 * sin(theta * 23.0 + y * 50.0)
			var progress := float(row) / 24.0
			r += volume * sin(progress * PI) * (1.0 + 0.10 * sin(theta * 13.0))
			points.append(Vector3(r * sin(theta), y + volume * progress * progress,
				HEAD_AXIS_Z - r * cos(theta)))
	for row in 24:
		for j in 64:
			var a := row * 64 + j
			var b := row * 64 + (j + 1) % 64
			_t3(st, points[a], points[b + 64], points[a + 64])
			_t3(st, points[a], points[b], points[b + 64])
	var crown := Vector3(0, 0.253 + volume, CRAN_C.z)
	for j in 64:
		_t3(st, crown, points[24 * 64 + j], points[24 * 64 + (j + 1) % 64])
	st.generate_normals()
	return st.commit()


static func _fitted_eye(head: Node3D, face: Array, side: float, cfg: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	var colors: Array[Color] = []
	var iris: Color = cfg.get("eye", Color(0.21, 0.13, 0.07))
	var skin: Color = cfg.skin
	# A 30 mm opening, 10 mm high, with pointed corners and a subtle canthal tilt.
	for row in 17:
		var radius := float(row) / 16.0
		for j in 64:
			var theta := TAU * float(j) / 64.0
			var dx := cos(theta) * radius * 0.015
			var dy := sin(theta) * pow(absf(sin(theta)), 0.35) * radius * 0.0055
			var x := side * 0.040 + dx
			var y := 0.127 + dy + side * dx * 0.065
			var z := _surface(face, x, y, true) - 0.0008 - 0.001 * (1.0 - radius * radius)
			points.append(Vector3(x, y, z))
			var color := Color(0.78, 0.79, 0.75)
			var radial := Vector2(dx, dy).length()
			if radial < 0.0058:   # M25: iris 10.6 -> 11.6 mm, pupil 4.8 -> 4.2 — a daylight eye
				color = iris.lightened(0.10 + 0.06 * sin(theta * 19.0))
				if radial > 0.0050:
					color = iris.darkened(0.42)
			if radial < 0.0021:
				color = Color(0.018, 0.016, 0.014)
			if Vector2(dx + 0.0014, dy - 0.0018).length() < 0.0007:
				color = Color(0.94, 0.95, 0.93)
			if radius > 0.91:
				color = skin.darkened(0.38 if dy > 0 else 0.12)
			colors.append(color)
	for row in 16:
		for j in 64:
			var a := row * 64 + j
			var b := row * 64 + (j + 1) % 64
			_ctri(st, points, colors, a, a + 64, b + 64)
			if row > 0:
				_ctri(st, points, colors, a, b + 64, b)
	st.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.38
	_put(head, st.commit(), Vector3.ZERO, material, Vector3.ONE, Vector3.ZERO)


static func _build_head(head: Node3D, cfg: Dictionary) -> void:
	var skin_c: Color = cfg["skin"]
	var rough := float(cfg.get("skin_rough", 0.72))
	var skin := _skin(skin_c, rough)
	var shade := _skin(skin_c.darkened(0.16), rough)
	var hair_c: Color = cfg["hair"]
	var hair := _m(hair_c, 0.92)
	# −1..1. Nobody's face is a mirror: one brow sits higher, one mouth corner
	# pulls. Two tenths of a millimetre of it is the difference between a person
	# and a mannequin at `face` range, and it costs no geometry.
	var whisk := int(cfg.get("whiskers", Whiskers.CLEAN))
	var beard_c := hair_c.lerp(skin_c, 0.18).darkened(0.05)
	var face := _face_masses(cfg)
	var p := _face_params(cfg)
	var asym := float(p[3])

	# ---- neck: rooted BELOW the collar line so the shirt swallows its base ----
	# M24: the skinned body (D-050) has a neck of its own in its field and a
	# collar band around it; there this rigid neck only hid both. Factory body
	# only.
	if not bool(cfg.get("skinned_body", false)):
		_limb(head, 0.056, 0.062, 0.19, Vector3(0, 0.015, 0.004), skin,
			Vector3(1, 1, 0.94), Vector3.ZERO, 0.0, 14)
		_ball(head, Vector3(0, -0.026, 0.030), Vector3(0.132, 0.10, 0.116), skin,
			Vector3.ZERO, 9, 16)  # nape
		for tx: float in [-1.0, 1.0]:                       # sternocleidomastoid
			_ball(head, Vector3(tx * 0.026, 0.026, -0.026),
				Vector3(0.030, 0.086, 0.030), skin, Vector3(0, 0, tx * 0.20), 5, 8,
				FACE_CULL)

	# ---- THE HEAD. One surface. See the M20 block for why.
	# Everything that used to be a separate ball here — cranium, jaw, chin, two
	# gonions, two jowls, two cheekbones, two brow ridges — plus the whole
	# mid-face menagerie below, is now relief on this mesh.
	_put(head, _head_mesh(p[0], p[1], p[2], p[3], p[4]), Vector3.ZERO,
		_skin(skin_c, rough, true), Vector3.ONE, Vector3.ZERO)
	for cx: float in [-1.0, 1.0]:
		_ear(head, cx, skin, shade)

	# Tapered, surface-fitted eyebrows; no overlapping bead silhouettes.
	for side: float in [-1.0, 1.0]:
		_brow_strip(head, face, side, asym, hair)

	# Eyes share the face's surface evaluator, including per-person proportions.
	for side: float in [-1.0, 1.0]:
		_fitted_eye(head, face, side, cfg)

	# ---- facial hair: laid ON the shell, in the HAIR colour ------------------
	# The M19 beard was three axis-aligned boxes and a ball placed against the
	# old jaw ellipsoid; against the new surface every one of them either floats
	# or sinks. Laid chains follow whatever the face actually does, and a chain
	# of small balls has no rim to lift (the M18 lesson that fixed the eyebrow).
	var bmat := _m(beard_c, 0.92)
	if whisk == Whiskers.MUSTACHE or whisk == Whiskers.GOATEE \
			or whisk == Whiskers.FULL:
		for k in 7:                                   # moustache over the philtrum
			var t := float(k) / 6.0 - 0.5
			_lay_ball(head, face, t * 0.048, 0.0805 - 0.0040 * absf(t) * 2.0,
				Vector3(0.016, 0.0125, 0.0075), bmat, 0.0016, 0.0, 4, 8, FACE_CULL)
	if whisk == Whiskers.GOATEE or whisk == Whiskers.FULL:
		for k in 5:                                              # chin patch
			var t := float(k) / 4.0 - 0.5
			_lay_ball(head, face, t * 0.040, 0.0470 - 0.0060 * absf(t) * 2.0,
				Vector3(0.022, 0.0300, 0.0080), bmat, 0.0020, 0.0, 4, 8, FACE_CULL)
	if whisk == Whiskers.FULL:
		# the jaw perimeter: sideburn down to the chin, both sides
		for k in 7:
			var t := float(k) / 6.0
			var by := lerpf(0.1060, 0.0430, t)
			var bxx := 0.0570 - 0.0230 * t * t
			for s: float in [-1.0, 1.0]:
				_lay_ball(head, face, s * bxx, by,
					Vector3(0.030, 0.030, 0.0085), bmat, 0.0022, 0.0, 4, 8)
		for k in 4:                                    # under the jaw / cheeks
			var t := float(k) / 3.0
			_lay_ball(head, face, 0.0, lerpf(0.0620, 0.0330, t),
				Vector3(0.060, 0.026, 0.0090), bmat, 0.0022, 0.0, 4, 10)
	elif whisk == Whiskers.STUBBLE:
		pass   # stubble is a tint baked into the shell (see `_face_tint`)

	_build_hair(head, cfg, hair, hair_c, face)
	_build_hat(head, cfg)


## An ear that survives the profile: a bowl, a helix rim over it, a tragus and a
## lobe. The M16 ear was one flat oval disc at x 0.078 — outside the skull's own
## half-width (0.077), so it hung off the silhouette AND got swallowed by the
## hat fringe, which is 0.084 wide.
static func _ear(head: Node3D, cx: float, skin: Material,
		shade: Material) -> void:
	# ONE plate laid against the skull, not a cluster: separate helix balls read
	# as a bunch of grapes at 1 m (M17 round 1). The bowl is a darker mass that
	# breaks the plate's outer face by 1 mm, so it reads as a recess, not a lump.
	_ball(head, Vector3(cx * 0.0655, 0.1175, 0.0195), Vector3(0.021, 0.056, 0.040),
		skin, Vector3(0.14, 0, cx * 0.09), 6, 12)
	_ball(head, Vector3(cx * 0.0715, 0.1155, 0.0230), Vector3(0.011, 0.032, 0.023),
		shade, Vector3(0.14, 0, cx * 0.09), 5, 10, FACE_CULL)        # concha
	_ball(head, Vector3(cx * 0.0640, 0.0965, 0.0145), Vector3(0.018, 0.024, 0.024),
		skin, Vector3.ZERO, 5, 10)                                   # lobe


## Hair with a HAIRLINE. A shell of hair reads as a helmet; what makes it read
## as hair is the edge — a fringe standing proud of the forehead and two temple
## recessions behind it. `face` is the skull surface so the fringe lands on the
## forehead rather than hovering in front of it.
static func _build_hair(head: Node3D, cfg: Dictionary, hair: Material,
		_hair_c: Color, _face: Array) -> void:
	var style := int(cfg.get("hairdo", Hairdo.SHORT))
	if style == Hairdo.BALD:
		return
	_put(head, _scalp_mesh(cfg), Vector3.ZERO, hair, Vector3.ONE, Vector3.ZERO)
	if style == Hairdo.LONG or style == Hairdo.TIED:
		var length := 0.19 if style == Hairdo.LONG else 0.13
		_ball(head, Vector3(0, 0.070, 0.080), Vector3(0.145, length, 0.100),
			hair, Vector3.ZERO, 12, 24)


## D-083(a): "the crown's rear silhouette carries a hard-edged rectangular step,
## as if a box had been subtracted from the top-rear of the hat." Measured, it
## was a box ADDED: the crown crease was a `_taper` standing 20 mm proud of the
## flat-brim's crown top (11 mm on the cowboy), 30 mm wide against a 212 mm
## crown, so from any angle off the centreline it cut a rectangle out of the
## outline. `round_limb` has a FLAT top cap, which is what invited a bar on top
## of it in the first place. A hat crown is domed and pinched: this closes the
## cylinder with a shallow dome whose equator matches the crown's own top radius
## (tangent, so no crease ring), then dents it with two darker side pinches that
## sit INSIDE the dome's silhouette — a cattleman crease you can read in shading
## without a single hard step in the outline.
static func _crown(head: Node3D, y: float, r: float, cz: float,
		shell: Material, pinch: Material) -> void:
	_ball(head, Vector3(0, y, cz), Vector3(r * 2.0, r * 0.44, r * 2.0), shell,
		Vector3.ZERO, 6, 20)
	for px: float in [-1.0, 1.0]:
		_ball(head, Vector3(px * r * 0.46, y + r * 0.12, cz),
			Vector3(r * 0.62, r * 0.34, r * 1.34), pinch, Vector3.ZERO, 5, 12,
			TRIM_CULL)


static func _build_hat(head: Node3D, cfg: Dictionary) -> void:
	var hc: Color = cfg.get("hat_color", Color(0.2, 0.2, 0.2))
	match int(cfg.get("hat", Hat.NONE)):
		Hat.CAP:
			var m := _m(hc, 0.85)
			var band := _m(hc.darkened(0.30), 0.85)
			# M21: the whole cap rides 12 mm higher. Its band bottom used to sit
			# at 0.154, i.e. BELOW the top of the eyebrows (0.1607) — the cap
			# itself was half of D-083's blindfold, and there was no room under
			# it for the fringe D-005 asks for. Verified the skull cannot poke
			# through at the new height: band radius 0.0824–0.0838 against a
			# cranium that measures 0.0760 at 0.166 and 0.0680 at 0.198.
			_ball(head, Vector3(0, 0.210, 0.024), Vector3(0.178, 0.132, 0.210), m,
					Vector3.ZERO, 10, 18)
			# M20: this ring was r 0.091 against a crown that is only 0.0806 wide
			# at the band's own height — a 10 mm lip standing off the hat it is
			# supposed to be part of (measured +15.8 mm off the skull). Sized to
			# the crown instead, so it reads as a seam in the cap.
			_limb(head, 0.0838, 0.0824, 0.032, Vector3(0, 0.182, 0.022), band,
				Vector3(1.0, 1.0, 1.13))
			_taper(head, Vector3(0.150, 0.016, 0.118), Vector2(0.112, 0.118),
				Vector3(0, 0.172, -0.130), m, Vector3(0.20, 0, 0))
			_ball(head, Vector3(0, 0.272, 0.024), Vector3(0.022, 0.020, 0.022), band,
				Vector3.ZERO, 4, 6)
			if bool(cfg.get("duty", false)):
				_taper(head, Vector3(0.036, 0.030, 0.010), Vector2(0.028, 0.010),
					Vector3(0, 0.194, -0.086), _badge(), Vector3.ZERO, Vector2.ZERO,
					TRIM_CULL)
		Hat.COWBOY:
			var hw := _m(hc, 0.9)
			var bd := _m(hc.darkened(0.35), 0.85)
			_ball(head, Vector3(0, 0.198, 0.006), Vector3(0.372, 0.034, 0.342), hw,
					Vector3.ZERO, 6, 26)
			_ball(head, Vector3(0, 0.186, -0.146), Vector3(0.226, 0.030, 0.104), hw,
					Vector3.ZERO, 6, 18)
			_limb(head, 0.098, 0.082, 0.150, Vector3(0, 0.286, 0.006), hw)
			_limb(head, 0.100, 0.100, 0.024, Vector3(0, 0.224, 0.006), bd,
				Vector3(1.02, 1, 1.02))
			_crown(head, 0.3575, 0.082, 0.006, hw, _m(hc.darkened(0.18), 0.9))
		Hat.FLAT_BRIM:
			# A rodeo flat-brim: WIDE brim, LOW crown. Round 1 gave Book a top
			# hat because the crown was 14 cm tall.
			#
			# M18: the brim reached z −0.168 while Book's face front is ≈ −0.08,
			# and at the shot hour the sun stands 64° up — so the brim's shadow
			# fell 34 mm behind its own edge and the WHOLE face was in shade,
			# every daylight hour, permanently. The canon silhouette is the wide
			# flat brim, so the width and the back stay; 21 mm comes off the
			# FRONT overhang only (the ellipse is shifted back as it is trimmed,
			# so the crown stays concentric) and the whole hat rides 5 mm higher.
			var hf := _m(hc, 0.9)
			var bf := _m(hc.darkened(0.35), 0.85)
			_ball(head, Vector3(0, 0.2030, 0.0130), Vector3(0.352, 0.024, 0.326),
					hf, Vector3.ZERO, 6, 26)
			_limb(head, 0.112, 0.106, 0.082, Vector3(0, 0.2420, 0.008), hf)
			_limb(head, 0.114, 0.114, 0.020, Vector3(0, 0.2130, 0.008), bf,
				Vector3(1.02, 1, 1.02))
			_crown(head, 0.2795, 0.106, 0.008, hf, _m(hc.darkened(0.16), 0.9))
		Hat.HARD_HAT:
			var hh := _m(hc, 0.42)
			_ball(head, Vector3(0, 0.210, 0.014), Vector3(0.198, 0.172, 0.218), hh,
					Vector3.ZERO, 10, 18)
			_ball(head, Vector3(0, 0.170, 0.008), Vector3(0.236, 0.028, 0.272), hh,
					Vector3.ZERO, 6, 22)
			_taper(head, Vector3(0.028, 0.026, 0.190), Vector2(0.020, 0.170),
				Vector3(0, 0.282, 0.014), hh)                            # centre rib
			_limb(head, 0.093, 0.093, 0.018, Vector3(0, 0.184, 0.012),
				_m(hc.darkened(0.22), 0.6), Vector3(1.02, 1, 1.12))
		Hat.BEANIE:
			var bm := _m(hc, 0.95)
			_ball(head, Vector3(0, 0.194, 0.022), Vector3(0.180, 0.156, 0.216), bm,
					Vector3.ZERO, 10, 18)
			_limb(head, 0.094, 0.094, 0.040, Vector3(0, 0.178, 0.020),
				_m(hc.lightened(0.12), 0.95), Vector3(1.0, 1.0, 1.10))


# ------------------------------ arms -----------------------------------------
static func _build_arms(collar: Node3D, rig: Dictionary, cfg: Dictionary,
		w: float, lg: float) -> void:
	var skin := _skin(cfg["skin"], float(cfg.get("skin_rough", 0.72)))
	var shirt := _m(cfg["shirt"], 0.92)
	var accent := _m(cfg.get("accent", Color(0.9, 0.9, 0.88)), 0.9)
	var long_sleeve := bool(cfg.get("sleeve_long", false))
	var gloves := bool(cfg.get("gloves", false))
	var glove := _m(Color(0.44, 0.35, 0.25), 0.9)
	var hand_mat := glove if gloves else skin

	for side in 2:
		var ax := -1.0 if side == 0 else 1.0
		var sh := Node3D.new()
		sh.position = Vector3(ax * SHOULDER_X * w, 0.0, 0.0)
		collar.add_child(sh)
		# M21 — THERE IS NO DELTOID BALL ANY MORE. It is the outer section of the
		# swept girdle on the collar, so the shoulder is one surface from the neck
		# to the point of the arm and there is nothing for a cap rim or a crease
		# to happen on. The arm's job is now only to be an arm.
		#
		# What that costs, stated plainly: the deltoid no longer rotates with the
		# shoulder joint. It is solved instead — the sleeve's top plane sits at
		# y −0.012, a 12 mm lever off the pivot, so at the gait's biggest arm
		# swing (ARM_SWING 0.5 × intensity 1.4 = 0.31 rad, hard-capped by
		# `animate`) the cap travels 3.7 mm in z inside a girdle whose local
		# half-depth there is 71.6 mm against a 60.7 mm sleeve. The cap cannot
		# come out at any speed the rig can reach.
		var arm_x := -ax * 0.008
		_limb(sh, 0.042 * lg, 0.058 * lg, 0.33, Vector3(arm_x, -0.172, 0), skin)
		if long_sleeve:
			_limb(sh, 0.045 * lg, 0.060 * lg, 0.333,
				Vector3(arm_x, -0.1785, 0), shirt)
		else:
			_limb(sh, 0.054 * lg, 0.062 * lg, 0.188,
				Vector3(arm_x, -0.106, 0), shirt)
			_limb(sh, 0.055 * lg, 0.054 * lg, 0.022,
				Vector3(arm_x, -0.190, 0), accent, Vector3.ONE,
				Vector3.ZERO, 42.0)                           # sleeve cuff band

		var el := Node3D.new()
		el.position = ELBOW_PIVOT
		sh.add_child(el)
		# The elbow ball bridges TWO flat caps — the upper arm's bottom and the
		# forearm's top. D-027 also filed it as an orb ("a second, smaller pair
		# at the elbows"), and measured it was: 108 mm across against a 94 mm
		# sleeve, i.e. 7 mm proud at the equator, with the sleeve's own cap disc
		# standing 5 mm OUTSIDE the ball at its own plane, which is the hard
		# bright ring. M21 makes it 40 % TALLER and slightly narrower (0.104 ×
		# 0.150 × 0.102): a long ellipsoid has a much gentler dR/dy where the
		# limbs meet it (0.42 instead of 1.06), so the join reads as a joint
		# swelling rather than a bead, and it now covers both caps with 1.1–1.8 mm
		# to spare at every girth in the roll.
		_ball(el, Vector3(arm_x, -0.012, 0.004),
			Vector3(0.104 * lg, 0.150, 0.102 * lg), shirt if long_sleeve else skin,
			Vector3.ZERO, 8, 14)
		# Forearm and hand splay OUTBOARD: at the M16 offsets the resting hand
		# sat at |x| 0.162 against a hip half-width of 0.184, i.e. buried in the
		# pelvis (visible from behind). A hanging hand clears the hip.
		var fx := ax * 0.002
		var hx := ax * 0.010
		_limb(el, 0.036 * lg, 0.046 * lg, 0.28, Vector3(fx, -0.135, 0), skin)
		if long_sleeve:
			_limb(el, 0.042 * lg, 0.050 * lg, 0.22, Vector3(fx, -0.108, 0), shirt)
			_limb(el, 0.043 * lg, 0.043 * lg, 0.026,
				Vector3(fx, -0.226, 0), accent)               # shirt cuff
		# hand: a flattened palm, a finger mass, a thumb — not a marble
		_ball(el, Vector3(hx, -0.290, -0.002), Vector3(0.040, 0.090, 0.078),
			hand_mat, Vector3.ZERO, 6, 10)
		_taper(el, Vector3(0.036, 0.080, 0.070), Vector2(0.032, 0.058),
			Vector3(hx, -0.360, -0.008), hand_mat)
		_ball(el, Vector3(hx - ax * 0.018, -0.312, -0.030),
			Vector3(0.024, 0.052, 0.028), hand_mat, Vector3.ZERO, 4, 8)

		rig["sh_%d" % side] = sh
		rig["el_%d" % side] = el


# ------------------------------ wardrobe layers ------------------------------
## Everything that makes a shirt an OUTFIT: collar, hem or belt, placket,
## pockets, vest, apron, hood, tie, duty gear. Ordered outside-in so the layers
## overlap the way cloth does.
static func _build_layers(torso: Node3D, collar: Node3D, rig: Dictionary,
		cfg: Dictionary, w: float, g: float, masses: Array) -> void:
	var shirt_c: Color = cfg["shirt"]
	var shirt := _m(shirt_c, 0.92)
	var accent_c: Color = cfg.get("accent", Color(0.9, 0.9, 0.88))
	var dep := clampf(0.74 + (g - 1.0) * 0.50, 0.66, 0.94)
	# (the old `chest_z` plane is gone — every piece that used it now reads the
	# real surface; see M20 notes on the lanyard, the drawstrings and the apron)
	var neck_style := int(cfg.get("neck", Neck.CREW))
	const CY := -0.56                     # collar space = torso space − pivot

	# ---- hem or belt: where the shirt meets the pants ----
	# A belt is its own barrel, so the buckle mounts on the BELT, not the hip.
	var belt_m: Array = []
	if bool(cfg.get("tucked", false)):
		if bool(cfg.get("belt", false)):
			var belt := _m(cfg.get("belt_color", LEATHER), 0.55)
			belt_m = [["limb", 0.160 * w * g, 0.164 * w * g, 0.1345, 0.1895,
				dep + 0.095, 0.0, 0]]
			_limb(torso, 0.160 * w * g, 0.164 * w * g, 0.055,
				Vector3(0, 0.162, 0), belt, Vector3(1, 1, dep + 0.095),
				Vector3.ZERO, 0.0, 16)
			if bool(cfg.get("buckle", false)):
				# M20: 80 mm of buckle on a 55 mm band overhung the belt top and
				# bottom, and measured +15.4 / +17.7 mm proud. A buckle sits ON
				# the belt: inside its height, and thin.
				_panel(torso, belt_m, 0.0, 0.163, Vector3(0.104, 0.050, 0.014),
					Vector2(0.092, 0.013), _buckle(), true, 0.0, 0.005)
				_panel(torso, belt_m, 0.0, 0.163, Vector3(0.070, 0.030, 0.009),
					Vector2(0.062, 0.008),
					_m(cfg.get("belt_color", LEATHER).lightened(0.25), 0.35),
					true, TRIM_CULL, 0.011)
			else:
				_panel(torso, belt_m, 0.0, 0.162, Vector3(0.052, 0.046, 0.016),
					Vector2(0.046, 0.014), _buckle(), true, 0.0, 0.007)
	else:
		# untucked hem: a flared band that stands PROUD of the waistband
		_limb(torso, 0.180 * w * g, 0.166 * w * g, 0.085,
			Vector3(0, 0.190, 0), shirt, Vector3(1, 1, dep + 0.075),
			Vector3.ZERO, 0.0, 16)

	# ---- collar ----
	var col_c := shirt_c
	if neck_style == Neck.DRESS or neck_style == Neck.SNAP:
		col_c = shirt_c.lerp(Color(1, 1, 1), 0.08)
	var col := _m(col_c, 0.9)
	match neck_style:
		Neck.CREW:
			_limb(collar, 0.076, 0.080, 0.046, Vector3(0, 0.042, 0.006),
				_m(shirt_c.darkened(0.10), 0.92), Vector3(1.06, 1, 1.06),
				Vector3.ZERO, 0.0, 14)
		Neck.VEE:
			_limb(collar, 0.078, 0.082, 0.042, Vector3(0, 0.036, 0.008),
				_m(accent_c, 0.92), Vector3(1.06, 1, 1.06), Vector3.ZERO, 0.0, 14)
			# M21: the 120 mm accent plate measured 19.7 mm of rim lift and the
			# skin wedge under it 11.3 mm. A V-neck is a notch, not a bib —
			# two shorter stacked plates, the upper one wide and the lower one
			# narrow, which is also what a V actually looks like.
			for i in 2:
				var vy := 0.4790 + 0.0430 * float(i)
				var vw := lerpf(0.046, 0.086, float(i))
				_panel(collar, masses, 0.0, vy, Vector3(vw, 0.048, 0.016),
					Vector2(lerpf(0.062, 0.108, float(i)), 0.016),
					_skin(cfg["skin"], float(cfg.get("skin_rough", 0.72))),
					true, 0.0, -0.004, CY)
				_panel(collar, masses, 0.0, vy - 0.002,
					Vector3(vw + 0.020, 0.052, 0.012),
					Vector2(lerpf(0.082, 0.128, float(i)), 0.012),
					_m(accent_c, 0.92), true, 0.0, 0.008, CY)
		Neck.HOODED:
			_ball(collar, Vector3(0, 0.020, 0.098),
				Vector3(0.250, 0.155, 0.155), _m(shirt_c.darkened(0.06), 0.92),
				Vector3.ZERO, 8, 14)
			_limb(collar, 0.086, 0.090, 0.055, Vector3(0, 0.040, 0.008),
				_m(shirt_c.darkened(0.06), 0.92), Vector3(1.08, 1, 1.08),
				Vector3.ZERO, 0.0, 14)
			if bool(cfg.get("hood_up", false)):
				var head: Node3D = rig["head"]
				_ball(head, Vector3(0, 0.148, 0.062),
					Vector3(0.250, 0.262, 0.244), _m(shirt_c.darkened(0.04), 0.92),
					Vector3.ZERO, 9, 16)
			for dx: float in [-1.0, 1.0]:
				# M20: these sat at a plane offset and measured −16..−20 mm, i.e.
				# buried, for their lower two thirds.
				var dz := _surface(masses, dx * 0.030, 0.540, true) - 0.008
				_limb(collar, 0.007, 0.007, 0.11,
					Vector3(dx * 0.030, -0.020, dz),
					_m(Color(0.86, 0.85, 0.82), 0.9))
		_:
			# snap / polo / dress: a stand collar plus two points ON the chest.
			# The M16 points were pinned 0.068 m in FRONT of a chest_z plane and
			# stuck out of the portrait like paper wings.
			_limb(collar, 0.080, 0.086, 0.050, Vector3(0, 0.046, 0.006), col,
				Vector3(1.08, 1, 1.08), Vector3.ZERO, 0.0, 14)
			for cx: float in [-1.0, 1.0]:
				# WIDE at the neck, tapering to a point at the sternum. M16 had
				# this taper upside down AND pinned 68 mm off a plane through
				# the chest, so both points flew off the portrait like paper
				# wings; M17 round 1 kept the inversion. size = the lower (point)
				# end, top = the upper (neck) end.
				_panel(collar, masses, cx * 0.040, 0.5115,
					Vector3(0.026, 0.042, 0.008), Vector2(0.048, 0.008), col,
					true, TRIM_CULL, -0.0015, CY, cx * 0.20)

	# ---- placket down the chest: three mounted segments, because one rigid
	# strip cannot follow a torso that curves in Y as well as X ----
	if neck_style != Neck.VEE and neck_style != Neck.HOODED \
			and not bool(cfg.get("jersey", false)):
		var plack := _m(shirt_c.darkened(0.07), 0.92)
		var lo := 0.300 if neck_style == Neck.POLO else 0.180
		var hi := 0.545
		# M21: THREE segments measured 7.0–11.7 mm of rim lift on all nine
		# configs I mirrored — always the TOP one, because a 130 mm rigid strip
		# has to span the pec swell AND the clavicle cone above it, and `_sag`
		# only sinks a piece by what the surface does ACROSS its width, never
		# along its height. Five shorter segments each follow the profile they
		# personally sit on. This is the cheapest fix in the file and it was
		# failing on every character in the game.
		var nseg := 8
		for i in nseg:
			var py := lerpf(lo, hi, (float(i) + 0.5) / float(nseg))
			_panel(torso, masses, 0.0, py,
				Vector3(0.038, (hi - lo) / float(nseg) + 0.005, 0.011),
				Vector2(0.036, 0.010), plack, true, 0.0, 0.0015)
		if bool(cfg.get("snaps", false)):
			# M20: `proud` 0.014 put the CENTRE of each snap 14 mm off the shirt
			# on a ball 6 mm in radius — measured +14.2 mm at the face and +8.0
			# at the REAR pole, i.e. the whole pearl was floating clear of the
			# cloth. A snap is a disc pressed into a placket: 3.5 mm of centre
			# offset on a 4.5 mm-deep dome leaves the back buried.
			var snap := _m2(Color(0.90, 0.90, 0.88), 0.20, 0.75)
			for i in 5:
				var sy := 0.520 - 0.078 * float(i)
				var l := _lay(masses, 0.0, sy, 0.0035)
				var sp: Vector3 = l[0]
				var sr: Vector3 = l[1]
				_ball(torso, sp, Vector3(0.019, 0.019, 0.009), snap, sr,
					4, 8, TRIM_CULL * 0.5)

	# ---- western yoke: the shoulder seam that says rodeo ----
	# M18. A yoke is a SEAM. M17 drew it as a 13 mm raised ring plus six mounted
	# boxes, and MEASURED, the ring sat 2–3 mm SUNK across the whole front and
	# only 2.3 mm proud at the flanks — so it vanished into the pec in the middle
	# and surfaced as two arcs at the sides, which is precisely how you build
	# something that reads as a tube laid on a chest. The boxes each took their
	# own yaw off the barrel and stepped against their neighbours: the
	# caterpillar.
	#
	# Both are now one thing: a chain of small laid BALLS, front and back. Balls
	# have no corners to step with and no rim to lift, and because every link is
	# placed on the surface it personally crosses, the relief is CONSTANT (1.7 to
	# 3.5 mm measured) all the way round instead of ducking in and out. Constant
	# relief is the whole difference between a seam and a tube.
	if bool(cfg.get("yoke", false)):
		var yk := _m(shirt_c.darkened(0.17), 0.92)
		for yx: float in [-1.0, 1.0]:          # front: a shallow V to the sternum
			for k in 5:
				var t := float(k) / 4.0
				_lay_ball(torso, masses, yx * (0.018 + 0.090 * t),
					0.4500 + 0.042 * t, Vector3(0.034, 0.0075, 0.0045), yk,
					0.0008, yx * 0.42, 4, 10, TRIM_CULL)
		for k in 9:            # back: across the blades, rising to each shoulder
			var t := float(k) / 8.0 - 0.5
			# M21: 60 mm links measured 6.1 mm at the outboard ends once the
			# girdle gave the shoulder a real (and steeper) surface to sit on.
			# Shorter links, less proud — a seam is 2 mm of relief or it is a tube.
			_lay_ball(torso, masses, t * 0.250, 0.4700 + 0.104 * t * t,
				Vector3(0.046, 0.0080, 0.0060), yk, 0.0011, 0.0, 4, 10,
				TRIM_CULL, 0.0, false)

	# ---- chest pockets: THE floating panel. Mounted on the plane through the
	# chest, a pocket's outer edge stood 2.9 cm off the shirt; laid on the
	# surface with its own yaw and pitch it sits on the cloth. ----
	if bool(cfg.get("pocket", false)):
		var pk := _m(shirt_c.darkened(0.10), 0.92)
		var sides: Array = [-1.0] if int(cfg.get("outfit", 0)) == Outfit.SCRUBS \
			else [-1.0, 1.0]
		for px: float in sides:
			_panel(torso, masses, px * 0.086, 0.424,
				Vector3(0.072, 0.076, 0.013), Vector2(0.066, 0.011), pk,
				true, 0.0, 0.005)
			_panel(torso, masses, px * 0.086, 0.464,
				Vector3(0.076, 0.015, 0.011), Vector2(0.070, 0.009), pk,
				true, TRIM_CULL, 0.008)                            # pocket flap

	# ---- jersey number band ----
	if bool(cfg.get("jersey", false)):
		# M20: a 150 mm rigid plate laid across a 160 mm-radius barrel lifts at
		# the corners no matter how it is sagged (measured +15.7 on the back
		# band). Narrower plates, and the sag now has something to work with.
		# M21: still 19.8 / 14.5 mm at the corners. A number is PRINTED on a
		# jersey — two shorter bands that each follow their own slice.
		var num := _m(accent_c, 0.9)
		for i in 3:
			var jy := 0.404 + 0.044 * float(i)
			_panel(torso, masses, 0.0, jy, Vector3(0.078 * w, 0.042, 0.010),
				Vector2(0.078 * w, 0.008), num, true, 0.0, 0.002)
			_panel(torso, masses, 0.0, jy, Vector3(0.064 * w, 0.044, 0.010),
				Vector2(0.064 * w, 0.008), num, false, 0.0, 0.002)

	# ---- tie ----
	if bool(cfg.get("tie", false)):
		# M21: measured 16.9 mm at the knot and 29.3 mm at the top of the upper
		# blade — the worst mounted piece in the whole population. A 130 mm rigid
		# blade laid tangent at its own centre lifts by whatever the chest does
		# over 65 mm of height, and above y 0.49 the chest is falling away fast.
		# Four 62 mm blades and a thinner, less proud knot.
		var tm := _m(cfg.get("tie_color", TIE_COLORS[0]), 0.7)
		_panel(collar, masses, 0.0, 0.5290, Vector3(0.036, 0.030, 0.018),
			Vector2(0.030, 0.017), tm, true, 0.0, 0.008, CY)
		for i in 5:
			var ty := 0.4880 - 0.0500 * float(i)
			_panel(torso, masses, 0.0, ty,
				Vector3(lerpf(0.034, 0.040, float(i) / 4.0), 0.054, 0.013),
				Vector2(lerpf(0.032, 0.038, float(i) / 4.0), 0.012), tm,
				true, 0.0, 0.006)

	# ---- lanyard + ID badge (office, scrubs) ----
	if bool(cfg.get("lanyard", false)):
		# M20: both cords hung at a fraction of a PLANE through the chest and
		# measured 33.9 mm INSIDE the shirt — they have never drawn, at any
		# height, on any build. Off the real surface instead.
		var lan := _m(Color(0.20, 0.24, 0.34), 0.9)
		for lx: float in [-1.0, 1.0]:
			var lz := _surface(masses, lx * 0.048, 0.530, true) - 0.007
			_limb(collar, 0.006, 0.006, 0.20, Vector3(lx * 0.048, -0.030, lz),
				lan, Vector3.ONE, Vector3(-0.14, 0, lx * 0.24))
		_panel(torso, masses, 0.0, 0.400, Vector3(0.050, 0.070, 0.008),
			Vector2(0.050, 0.008), _m(Color(0.88, 0.88, 0.86), 0.4),
			true, 0.0, 0.006)

	# ---- hi-vis vest: back shell, two front panels, straps, reflective bands --
	if bool(cfg.get("vest", false)):
		var hv := _m(cfg.get("vest_color", HIVIS[0]), 0.62)
		var rf := _m(REFLECTIVE, 0.28)
		var shell: Array = [["ball", Vector3(0, 0.430, 0.074),
			Vector3(0.336 * w, 0.320, 0.166), 1]]
		_ball(torso, Vector3(0, 0.430, 0.074), Vector3(0.336 * w, 0.320, 0.166),
			hv, Vector3.ZERO, 10, 20)
		for vx: float in [-1.0, 1.0]:
			# M16 yawed these by +vx*0.34, which flares the OUTER edge forward —
			# the exact opposite of wrapping a barrel. _panel derives the sign.
			_panel(torso, masses, vx * 0.080, 0.424,
				Vector3(0.104, 0.300, 0.026), Vector2(0.098, 0.024), hv,
				true, 0.0, 0.014)
			_taper(torso, Vector3(0.086, 0.030, 0.180), Vector2(0.080, 0.170),
				Vector3(vx * 0.108, 0.556, 0.004), hv, Vector3(0, 0, vx * 0.18))
			for by: float in [0.494, 0.368]:
				_panel(torso, masses, vx * 0.080, by,
					Vector3(0.100, 0.024, 0.020), Vector2(0.096, 0.020), rf,
					true, TRIM_CULL, 0.026)
		for bi in 3:
			_panel(torso, shell, (float(bi) - 1.0) * 0.076 * w, 0.420,
				Vector3(0.068 * w, 0.026, 0.014), Vector2(0.066 * w, 0.026), rf,
				false, TRIM_CULL, 0.004)

	# ---- apron ----
	if bool(cfg.get("apron", false)):
		var apron_c: Color = cfg.get("apron_color", APRON_COLORS[0])
		# M21: the bib measured 11.0 mm and the skirt 23.3 mm of rim lift — a
		# 290 mm rigid board hung on a barrel. Five shorter courses, each laid on
		# the slice it covers, which is also how a bib apron hangs.
		var ap := _m(apron_c, 0.9)
		for i in 7:
			var ay := 0.462 - 0.052 * float(i)
			var aw := lerpf(0.140, 0.160, float(i) / 6.0)
			_panel(torso, masses, 0.0, ay, Vector3(aw, 0.060, 0.022),
				Vector2(aw * 0.95, 0.020), ap, true, 0.0, 0.009)
		for sx: float in [-1.0, 1.0]:
			var az := _surface(masses, sx * 0.052, 0.520, true) - 0.009
			_limb(torso, 0.009, 0.009, 0.14, Vector3(sx * 0.052, 0.520, az),
				ap, Vector3.ONE, Vector3(0, 0, sx * 0.34))
		_panel(torso, masses, -0.060, 0.255, Vector3(0.070, 0.062, 0.014),
			Vector2(0.070, 0.012), _m(apron_c.darkened(0.2), 0.9), true,
			TRIM_CULL, 0.026)                                       # apron pocket

	# ---- duty gear (D-017 officers) ----
	if bool(cfg.get("duty", false)):
		var duty := _m(DUTY_BLACK, 0.5)
		var duty_m: Array = [["limb", 0.166 * w * g, 0.170 * w * g, 0.129, 0.191,
			dep + 0.115, 0.0, 0]]
		_panel(torso, masses, -0.080, 0.452, Vector3(0.048, 0.058, 0.012),
			Vector2(0.040, 0.010), _badge(), true, TRIM_CULL, 0.006)  # shield
		_panel(torso, masses, 0.080, 0.462, Vector3(0.098, 0.018, 0.010),
			Vector2(0.098, 0.008), _m(Color(0.88, 0.88, 0.86), 0.6), true,
			TRIM_CULL, 0.005)                                       # name tape
		for ex: float in [-1.0, 1.0]:                                # epaulets
			# M20: 96 mm long on a shoulder that falls away 34 mm across that
			# span — the forward corner measured +15.7 mm off the cloth. Short
			# enough to lie on the flat of the trapezius.
			_taper(torso, Vector3(0.050, 0.015, 0.058), Vector2(0.042, 0.052),
				Vector3(ex * 0.132, 0.5735, 0.004),
				_m(COP_SHIRT.darkened(0.18), 0.9))
		# belt gear: holster right, radio left, pouches front — all above the
		# thigh so nothing clips through the walk cycle
		_limb(torso, 0.166 * w * g, 0.170 * w * g, 0.062, Vector3(0, 0.160, 0),
			duty, Vector3(1, 1, dep + 0.115), Vector3.ZERO, 0.0, 16)
		_taper(torso, Vector3(0.052, 0.120, 0.056), Vector2(0.046, 0.050),
			Vector3(0.150, 0.098, 0.020), duty)                     # holster
		_taper(torso, Vector3(0.038, 0.086, 0.036), Vector2(0.034, 0.032),
			Vector3(-0.148, 0.106, 0.014), duty)                    # radio
		_panel(torso, duty_m, -0.078, 0.156, Vector3(0.046, 0.048, 0.032),
			Vector2(0.042, 0.030), duty, true, TRIM_CULL, 0.014)    # mag pouch
		_panel(torso, duty_m, 0.080, 0.156, Vector3(0.044, 0.044, 0.030),
			Vector2(0.040, 0.028), duty, true, TRIM_CULL, 0.013)    # cuff case
		_taper(torso, Vector3(0.030, 0.036, 0.016), Vector2(0.026, 0.014),
			Vector3(-0.108, 0.548, -0.030), duty)                   # shoulder mic


# ============================== ANIMATION ====================================
## Procedural gait. Legs swing out of phase, knees only bend backward, arms
## counter-swing the legs, the body bobs twice per stride and leans into
## speed. At rest everything eases back to a neutral stand.
##   speed  planar m/s
##   moving whether the character intends to move (idle vs walk)
static func animate(rig: Dictionary, speed: float, delta: float,
		moving: bool, grounded := true) -> void:
	if rig.is_empty() or not is_instance_valid(rig.get("vis")):
		return
	var intensity := clampf(speed / REF_SPEED, 0.0, 1.4)
	# Phase advances with DISTANCE, so feet never skate at any speed.
	var phase := float(rig["phase"]) + speed * delta * TAU * STRIDE_PER_M * 0.5
	rig["phase"] = fmod(phase, TAU)
	var k := 1.0 - exp(-BLEND * delta)
	var swing := 0.0
	var bob := 0.0
	var lean := 0.0
	if moving and speed > 0.15 and grounded:
		swing = sin(phase)
		bob = absf(sin(phase)) * BOB_H * intensity
		lean = LEAN_MAX * intensity
	elif not grounded:
		swing = 0.35  # legs tuck slightly in the air
	var hs := HIP_SWING * intensity * swing
	var arm := -ARM_SWING * intensity * swing
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		var hip: Node3D = rig["hip_%d" % side]
		var knee: Node3D = rig["knee_%d" % side]
		var sh: Node3D = rig["sh_%d" % side]
		var el: Node3D = rig["el_%d" % side]
		hip.rotation.x = lerp_angle(hip.rotation.x, hs * sgn, k)
		# Knee bends only one way, and most on the recovery (rear) swing.
		var bend := maxf(-sin(phase * 1.0 + 0.9) * sgn, 0.0) * KNEE_BEND * intensity
		if not grounded:
			bend = 0.5
		knee.rotation.x = lerp_angle(knee.rotation.x, -bend, k)
		sh.rotation.x = lerp_angle(sh.rotation.x, arm * sgn, k)
		# JOINT SIGN LAW (M16 fix — a limb hangs down -Y, so a POSITIVE
		# rotation.x swings it toward -Z = FORWARD):
		#   knee flexion is BACKWARD -> negative (heel to butt) — correct above
		#   elbow flexion is FORWARD -> POSITIVE
		# M10 gave the elbow the knee's sign, so every arm in the game bent
		# backwards at the elbow from M10 until now (Milad: "when ppl walk the
		# elbows are backwards"). Knees and elbows are mirror joints; they can
		# never share a sign.
		el.rotation.x = lerp_angle(el.rotation.x,
			ELBOW_BEND * (0.4 + 0.6 * intensity) if moving else 0.12, k)
	var torso: Node3D = rig["torso"]
	torso.rotation.x = lerp_angle(torso.rotation.x, lean, k)
	torso.rotation.z = lerp_angle(torso.rotation.z, -0.04 * intensity * sin(phase), k)
	var head: Node3D = rig["head"]
	head.rotation.x = lerp_angle(head.rotation.x, -lean * 0.7, k)  # eyes stay level
	var vis: Node3D = rig["vis"]
	if not rig.has("base_y"):
		rig["base_y"] = vis.position.y   # the feet line this rig was built at
	rig["bob"] = lerpf(float(rig["bob"]), bob, k)
	vis.position.y = float(rig["base_y"]) + float(rig["bob"])


## Shooter stance: square up, gun arm forward. Called instead of a gait step.
static func aim_pose(rig: Dictionary, delta: float) -> void:
	if rig.is_empty() or not is_instance_valid(rig.get("vis")):
		return
	var k := 1.0 - exp(-BLEND * delta)
	var sh_r: Node3D = rig["sh_1"]
	var el_r: Node3D = rig["el_1"]
	var sh_l: Node3D = rig["sh_0"]
	var el_l: Node3D = rig["el_0"]
	# Same sign law as animate(): POSITIVE = the arm comes FORWARD, which is
	# the whole point of a shooter stance. These were negative (gun arm swung
	# BEHIND the body) for the same M10 reason.
	sh_r.rotation.x = lerp_angle(sh_r.rotation.x, 1.45, k)
	el_r.rotation.x = lerp_angle(el_r.rotation.x, 0.12, k)
	sh_l.rotation.x = lerp_angle(sh_l.rotation.x, 1.15, k)
	el_l.rotation.x = lerp_angle(el_l.rotation.x, 0.5, k)
	sh_l.rotation.z = lerp_angle(sh_l.rotation.z, -0.35, k)


# ============================== PLUMBING =====================================
static func _buckle() -> StandardMaterial3D:
	return _m2(Color(0.85, 0.7, 0.3), 0.22, 0.85)


static func _badge() -> StandardMaterial3D:
	return _m2(Color(0.86, 0.74, 0.36), 0.18, 0.9)


static func _m(c: Color, rough: float) -> StandardMaterial3D:
	return _m2(c, rough, 0.0)


static func _m2(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(true), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## Faintly self-lit. Reserved for the eye: a sclera that goes to pure black
## under a hat brim is the whole "dark blobs / goggles" complaint, and Book
## wears a flat-brim in every shot. No emission TEXTURE is set, so D-011's
## emission_operator=ADD trap (a white emission colour beside a texture blowing
## a whole facade out) cannot bite; energies stay under the 1.05 glow threshold.
## Skin, with the head shell's baked vertex colours read as a MULTIPLIER on it.
## That is what lets lips, the mouth seam and nostrils live on one cached mesh
## that every skin tone in the palette can wear: the tint is a ratio, never a
## colour, so no sRGB conversion applies to it (the D-018 instance-colour trap
## bites absolute colours, not multipliers — 1.0 is 1.0 in either space).
## SKIN. Splitting this out of `_m` is the whole point: `_m` paints shirts,
## boots and hard hats, and none of those should scatter light through
## themselves. Only the five sites that are actually flesh call this — legs,
## head, ear shading, arms, and exposed skin under a wardrobe layer — plus the
## head shell through `vertex_color = true`.
##
## `vertex_color` carries the head shell's baked nose/lip/brow relief, which the
## shader multiplies exactly the way `_mvc` did (a ratio, never a colour — the
## D-018 sRGB instance-colour trap bites absolute colours, and 1.0 is 1.0 in
## either space).
static func _skin(c: Color, rough: float, vertex_color := false) -> Material:
	if SHD.legacy():
		return _mvc(c, rough) if vertex_color else _m(c, rough)
	var key := "sk%s_%.2f_%s" % [c.to_html(true), rough, vertex_color]
	if not _mats.has(key):
		_mats[key] = SHD.skin_material(c, rough, vertex_color)
	return _mats[key]


static func _mvc(c: Color, rough: float) -> StandardMaterial3D:
	var key := "v%s_%.2f" % [c.to_html(true), rough]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]


static func _m3(c: Color, rough: float, emit: float) -> StandardMaterial3D:
	var key := "e%s_%.2f_%.2f" % [c.to_html(true), rough, emit]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]


## One place where a part becomes a node — position, then LOCAL rotation, then
## LOCAL scale (Node3D composes scale inside the rotation, so no shear: the
## `Basis.scaled()` global-axis trap logged in D-013 cannot bite here).
##
## `vis_end` is the distance past which the part stops drawing. An iris is two
## centimetres across: nobody sees it from across the street, and a crowd of
## sixteen people should not pay for sixteen sets of them. Face micro-detail
## culls at FACE_CULL, wardrobe trim at TRIM_CULL; every silhouette-carrying
## mass draws forever.
const FACE_CULL := 16.0
const TRIM_CULL := 42.0

static func _put(parent: Node3D, mesh: Mesh, pos: Vector3,
		mat: Material, scl: Vector3, rot: Vector3,
		vis_end := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	if scl != Vector3.ONE:
		mi.scale = scl
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = vis_end * 0.12
	parent.add_child(mi)


## Box with an independently sized top face — collars, plackets, soles, pockets.
static func _taper(parent: Node3D, size: Vector3, top: Vector2, pos: Vector3,
		mat: Material, rot := Vector3.ZERO,
		top_shift := Vector2.ZERO, vis_end := 0.0) -> void:
	_put(parent, KIT.taper(size, top, top_shift), pos, mat, Vector3.ONE, rot,
		vis_end)


## Smooth tapered round limb; `scl` squashes it (torsos are wider than deep).
## `sides` defaults to 12 (was 9 through M16): a 9-gon's front facet spans 40
## degrees, which is why a chest photographed as a sheet of cardboard at 1 m.
## Torso barrels pass 16.
static func _limb(parent: Node3D, r_bottom: float, r_top: float, length: float,
		pos: Vector3, mat: Material, scl := Vector3.ONE,
		rot := Vector3.ZERO, vis_end := 0.0, sides := 12) -> void:
	_put(parent, KIT.round_limb(r_bottom, r_top, length, sides), pos, mat, scl,
		rot, vis_end)


## Unit sphere scaled to `dia` (full diameters per axis). Small features drop
## to a coarser sphere — nobody counts facets on a nostril.
## M17 had to carry a private copy of the sphere builder because `KIT.sphere()`
## had emitted inside-out geometry since M15 and the kit belonged to another
## agent that milestone. The kit is fixed at the source now (its winding was
## checked triangle-for-triangle against this copy before the copy was retired),
## so the people share the kit's cache with the trees, the water tanks and the
## church orb again instead of baking a second set of the same meshes.
static func _ball(parent: Node3D, pos: Vector3, dia: Vector3,
		mat: Material, rot := Vector3.ZERO, rings := 7,
		segs := 12, vis_end := 0.0) -> void:
	_put(parent, KIT.sphere(0.5, rings, segs), pos, mat, dia, rot, vis_end)
