extends Node
## AMBIENCE v1 — the bed the city sits on. Six looping layers, all synthesized
## at setup into AudioStreamWAV buffers (16-bit mono 22050 Hz, built once, zero
## per-frame allocation), cross-faded by where the player is, what hour it is,
## and what the sky is doing. Plus one rare punctuation voice (far horn, dog,
## train, distant siren, car door) on a long random interval.
##
## SEAMLESS BY CONSTRUCTION, three ways:
##   * tonal drones are placed by INTEGER CYCLE COUNT over the buffer, so they
##     close the loop exactly (no frequency rounding);
##   * every noise bed is filtered CIRCULARLY (`_ring_lp` runs a warm-up lap so
##     the filter state at sample 0 is exactly the state after sample n-1) —
##     strictly better than a crossfade, because nothing is faked;
##   * every chirp/whistle/pulse is windowed to silence at both ends and
##     written with wrap-around (`% n`), the radio's idiom.
##
## MIX LAW: ambience sits UNDER everything. Beds normalize to 0.24 RMS
## (-12.4 dBFS) and play at -18..-26 dB, so the loudest single layer nets
## -30.4 dBFS RMS and a worst-case four-layer stack nets ~-27 dBFS RMS. The
## engine peaks at -8, gunfire at -6/-4, sirens at -12: nothing here can mask
## any of them, and the whole bed ducks another 10.5 dB when a storm is up
## because rain owns that mix.
##
## PEERS ARE READ-ONLY. sky_weather's clock, storm mix and night flag are read
## null-safe (this file sorts FIRST in scripts/systems, so the peer does not
## exist yet at setup — it is resolved lazily). Nothing here writes to another
## system, ever.
##
## ENTIRELY INERT in smoke mode: no buffers, no bus, no players, no processing.

# ============================== TUNABLES =====================================
const RNG_SEED := 0xAB1E                   # every noise/placement draw
const MIX_RATE := 22050                    # Hz, all buffers

# ---- Regions -----------------------------------------------------------------
# Local read-only copies of greybox_city's layout numbers: the soundscape must
# survive the city script being renamed, refactored, or partially built.
# Downtown = the 8x6 tower grid (x 120..782, z 60..550) plus the hospital
# campus, widened south over the frontage strip so the deck under downtown
# still hears the city. Suburb = SUB_RECT, padded. Everything else (prairie,
# floodway cut, map edges) is PRAIRIE.
const DOWNTOWN_RECT := Rect2(95.0, -20.0, 720.0, 700.0)     # x 95..815, z -20..680
const SUBURB_RECT := Rect2(-620.0, -900.0, 1340.0, 740.0)   # x -620..720, z -900..-160
## Hysteresis: you must be this far OUTSIDE a rect before it lets go of you.
## A boundary walk therefore cannot chatter — the flip needs 30 m of commitment.
const REGION_HYST := 30.0

# ---- Freeway proximity (a continuous term, not a region) ---------------------
const FWY_HALF_LEN := 800.0                # deck runs |x| <= 800
const FWY_HALF_W := 12.0                   # deck is 24 m wide, centred on z = 0
const FWY_AUDIBLE := 175.0                 # tire roar reaches this far
const FWY_CURVE := 1.7                     # >1 = holds up near the deck, dies fast far

# ---- Cross-fade --------------------------------------------------------------
const FADE_S := 1.8                        # full 0->1 layer cross-fade time
const CUT_W := 0.004                       # below this weight a layer stops
const DB_EPSILON := 0.05                   # skip redundant volume_db writes

# ---- The mix (dB on each layer at weight 1.0) -------------------------------
const L_CITY := 0
const L_FREEWAY := 1
const L_WIND := 2
const L_CICADA := 3
const L_CRICKET := 4
const L_BIRD := 5
const LAYER_COUNT := 6
const LAYER_NAMES: Array[String] = ["city", "freeway", "wind", "cicada", "cricket", "bird"]
const LAYER_DB: Array[float] = [
	-22.0,   # CITY    traffic hum + HVAC drone, full downtown
	-18.0,   # FREEWAY tire roar standing on the shoulder of the deck
	-24.0,   # WIND    open prairie, or a full storm gust
	-22.0,   # CICADA  dusk rasp
	-24.0,   # CRICKET night field
	-26.0,   # BIRD    dawn chorus
]
## In-car spectral tilt. The layers are already a filter bank (rumble / mid
## roar / broadband / 4.5 kHz insects / 2-4 kHz birds), so tilting them IS a
## low-pass — the bus filter below then does the continuous part.
const LAYER_CAB_DB: Array[float] = [-3.0, -6.0, -8.0, -15.0, -16.0, -15.0]
const CAB_TRIM_DB := -5.0                  # plus a flat cut: the cab is quieter
const MUFFLE_S := 0.4                      # door-close / door-open sweep time
const BUS_NAME := "Ambience"
const LP_OPEN_HZ := 20500.0                # on foot: effectively bypassed
const LP_CAB_HZ := 760.0                   # in the cab: glass and steel

# ---- Region -> base layer weights -------------------------------------------
# Columns are the layer indices above. FREEWAY is 1.0 everywhere because its
# real level comes from proximity; the column stays so it can be shaped later.
const REG_DOWNTOWN := 0
const REG_SUBURB := 1
const REG_PRAIRIE := 2
const REGION_NAMES: Array[String] = ["downtown", "suburb", "prairie"]
const REGION_MIX: Array = [
	[1.00, 1.00, 0.16, 0.30, 0.26, 0.50],   # DOWNTOWN — the hum owns it
	[0.24, 1.00, 0.52, 1.00, 1.00, 1.00],   # SUBURB   — the porch mix
	[0.05, 1.00, 1.00, 0.62, 0.70, 0.80],   # PRAIRIE  — wind, bugs, sparse birds
]

# ---- Time of day (hours, read off sky_weather) ------------------------------
const DEFAULT_HOUR := 13.0                 # sky_weather absent: an ordinary noon
const BIRD_DAY_FLOOR := 0.35               # the dawn chorus settles to a murmur
const BIRD_EVENING := 0.60                 # small pre-dusk uptick
const CICADA_DAY := 0.50                   # they start in the afternoon heat
const NIGHT_QUIET := 0.45                  # 03:00 thinning of city/freeway
const NIGHT_QUIET_HOUR := 3.0
const NIGHT_QUIET_SPAN := 5.0              # dip spans 22:00 -> 08:00

# ---- Weather (read-only from sky_weather) -----------------------------------
const STORM_DUCK := 0.30                   # -10.5 dB on the bed when rain is up
const STORM_BUG_KILL := 0.90               # bugs and birds shut up in the rain
const WIND_GUST_HZ := 0.35                 # mirrors sky_weather's gust rate
const STORM_WIND_LO := 0.25                # storm wind floor / gust peak
const STORM_WIND_HI := 0.85

# ---- Punctuation one-shots ---------------------------------------------------
const SH_HORN := 0
const SH_DOG := 1
const SH_TRAIN := 2
const SH_SIREN := 3
const SH_DOOR := 4
const SHOT_COUNT := 5
const SHOT_NAMES: Array[String] = ["horn", "dog", "train", "siren", "door"]
const SHOT_DB: Array[float] = [-30.0, -29.0, -27.0, -34.0, -31.0]
## Repeated entries are the weights. Kept deliberately thin — a punctuation you
## hear twice in a minute is worse than silence.
const SHOT_POOL: Array = [
	[SH_HORN, SH_HORN, SH_HORN, SH_SIREN, SH_DOOR, SH_DOOR],           # DOWNTOWN
	[SH_DOG, SH_DOG, SH_DOG, SH_DOOR, SH_DOOR, SH_HORN, SH_TRAIN],     # SUBURB
	[SH_TRAIN, SH_TRAIN, SH_DOG, SH_HORN],                             # PRAIRIE
]
const SHOT_MIN_S := 34.0
const SHOT_MAX_S := 88.0
const SHOT_STORM_MAX := 0.5                # above this storm mix, nothing punctuates

# ---- Buffer lengths (seconds -> samples; all even, all whole loops) ---------
const CITY_SAMPLES := 176400               # 8.0 s
const FWY_SAMPLES := 198450                # 9.0 s
const WIND_SAMPLES := 220500               # 10.0 s
const CICADA_SAMPLES := 132300             # 6.0 s
const CRICKET_SAMPLES := 176400            # 8.0 s
const BIRD_SAMPLES := 264600               # 12.0 s
const BED_RMS := 0.24                      # -12.4 dBFS RMS, every bed
const BED_PEAK_CAP := 0.88                 # ... unless that would clip
const WORK_RMS := 0.30                     # intermediate signals, uncapped
const NO_CAP := 99.0
const MOD_SIZE := 2048                     # slow-modulator table (power of 2)
const MOD_MASK := 2047

## Five passing vehicles per freeway loop: [position 0..1, half-width s, gain].
## Each hump lifts the level AND opens the brightness, so a car reads as
## approaching-and-gone rather than a volume knob.
const FWY_PASSES: Array = [
	[0.07, 0.55, 0.62], [0.31, 0.38, 0.44], [0.52, 0.70, 0.75],
	[0.74, 0.30, 0.36], [0.93, 0.48, 0.55],
]
const FWY_FLOOR := 0.42                    # the constant far-field roar

## Cicadas: [tymbal cycles over the 6 s loop, swell cycles, phase, gain].
## Integer cycle counts -> every modulator closes the loop exactly.
## 540/6 = 90 Hz tymbal, 576/6 = 96, 504/6 = 84, 612/6 = 102.
const CICADA_VOICES: Array = [
	[540, 3, 0.0, 1.00], [576, 2, 2.1, 0.70],
	[504, 4, 4.4, 0.55], [612, 3, 1.2, 0.42],
]
const CRICKET_COUNT := 7
const BIRD_MOTIFS := 11

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _streams: Array[AudioStreamWAV] = []
var _shot_streams: Array[AudioStreamWAV] = []
var _players: Array[AudioStreamPlayer] = []
var _shot: AudioStreamPlayer = null
var _lp: AudioEffectLowPassFilter = null
var _bus_made := false
var _w := PackedFloat32Array()             # live weights (cross-faded)
var _wt := PackedFloat32Array()            # target weights (recomputed each tick)
var _last_db := PackedFloat32Array()       # last written volume, to skip no-ops
var _region := REG_PRAIRIE
var _muffle := 0.0                         # 0 = on foot, 1 = sealed in the cab
var _last_muffle := -1.0
var _gust_t := 0.0
var _shot_t := 0.0
var _sky: Node = null                      # resolved lazily (we load first)
var _police: Node = null
var _peer_t := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true            # SMOKE SAFETY: no buffers, no bus, no players
		set_physics_process(false)
		set_process(false)
		return
	set_process(false)              # physics tick only
	_rng.seed = RNG_SEED
	_w.resize(LAYER_COUNT)
	_wt.resize(LAYER_COUNT)
	_last_db.resize(LAYER_COUNT)
	for i in LAYER_COUNT:
		_last_db[i] = -999.0
	_build_streams()
	_make_bus()
	for i in LAYER_COUNT:
		_players.append(_make_voice(_streams[i], LAYER_DB[i]))
	_shot = _make_voice(null, SHOT_DB[SH_HORN])
	_shot_t = _rng.randf_range(SHOT_MIN_S, SHOT_MAX_S)
	# Start in whatever region we spawned in, at full weight, so boot is not a
	# 2 s fade-up from nothing.
	_region = _pick_region(_player_pos())
	_compute_targets(_region, _freeway_prox(_player_pos()), DEFAULT_HOUR, 0.0, 0.5)
	for i in LAYER_COUNT:
		_w[i] = _wt[i]


func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	_peer_t -= delta
	if _peer_t <= 0.0:
		_peer_t = 1.0
		_resolve_peers()
	_gust_t += delta
	var pos := _player_pos()
	_region = _pick_region(pos)
	var gust := 0.5 + 0.5 * sin(_gust_t * TAU * WIND_GUST_HZ)
	_compute_targets(_region, _freeway_prox(pos), _hour(), _storm(), gust)
	var step := delta / FADE_S
	for i in LAYER_COUNT:
		_w[i] = move_toward(_w[i], _wt[i], step)
	# On foot the bed is open; in the cab it is quieter and low-passed.
	_muffle = move_toward(_muffle, 0.0 if _on_foot() else 1.0, delta / MUFFLE_S)
	_apply_filter()
	_apply_levels()
	_update_shots(delta)


## AUDIO LAW (Godot 4.7.1 leaks playing streams at quit): stop everything on
## teardown, and hand the AudioServer back exactly the bus layout it had.
func _exit_tree() -> void:
	# Order matters. Kill our own ticking FIRST: _process cross-fades layers and
	# can re-`play()` a voice we just stopped, which is how a bed ended up
	# mid-playback at quit — and 4.7.1 leaks the STREAM of anything still
	# playing during teardown (the M4 lesson). Intermittent 6-object leak
	# (= the 6 beds), reproduced 1 run in 4 before this.
	set_process(false)
	set_physics_process(false)
	_stop_all()
	if _bus_made:
		for p: AudioStreamPlayer in _players:
			if is_instance_valid(p):
				p.bus = &"Master"
		if _shot != null and is_instance_valid(_shot):
			_shot.bus = &"Master"
		var idx := AudioServer.get_bus_index(BUS_NAME)
		if idx >= 1:
			AudioServer.remove_bus(idx)   # removing the bus drops its effects
		_lp = null                        # release our own handle
		_bus_made = false
	# M19: stopping and nulling the stream was still leaving ~47% of boots with
	# 6 leaked objects (= the bed count) — the AudioStreamPlayback the server
	# made for each voice outlives a mere stop() during teardown. Free the
	# player nodes ourselves, NOW rather than deferred: we own them, they are
	# leaving anyway, and an immediate free releases their playback before the
	# ObjectDB census runs.
	for p: AudioStreamPlayer in _players:
		if is_instance_valid(p):
			p.free()
	_players.clear()
	if _shot != null and is_instance_valid(_shot):
		_shot.free()
	_shot = null


## Stop AND release. Dropping `stream` is the part that matters at quit: a
## stopped player still holds a reference to its AudioStreamWAV, and that
## reference is what shows up in the ObjectDB leak count.
func _stop_all() -> void:
	for p: AudioStreamPlayer in _players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	if _shot != null and is_instance_valid(_shot):
		_shot.stop()
		_shot.stream = null
	# Drop OUR references too. The players were only one holder; these arrays
	# keep all 6 beds + the one-shots alive, and at quit the ObjectDB census
	# can run before this node's members are collected — which is why the leak
	# was exactly 6 (the bed count) and why nulling the players alone did not
	# clear it. Verified by A/B: 6/6 clean boots with ambience removed.
	_streams.clear()
	_shot_streams.clear()


# ============================== RUNTIME ======================================
## Every player lives on this system node, which is never freed — but the leak
## law wants belt AND braces, so each one also self-stops on tree exit.
func _make_voice(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	if _bus_made:
		p.bus = BUS_NAME
	p.tree_exiting.connect(p.stop)
	add_child(p)
	return p


## A private bus carrying only ambience, so the cab low-pass cannot touch the
## engine, the radio, gunfire or a siren. Removed again in _exit_tree.
func _make_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) >= 0:
		_bus_made = true            # already installed (defensive: re-setup)
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, &"Master")
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = LP_OPEN_HZ
	AudioServer.add_bus_effect(idx, _lp)
	_bus_made = true


func _resolve_peers() -> void:
	# This file sorts first in scripts/systems, so at setup() the systems dict
	# holds only us. Resolve peers lazily, and re-resolve if one goes away.
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary):
		return
	var d := sys as Dictionary
	if _sky == null or not is_instance_valid(_sky):
		var s: Variant = d.get("sky_weather")
		_sky = s if (s is Node and is_instance_valid(s)) else null
	if _police == null or not is_instance_valid(_police):
		var c: Variant = d.get("police")
		_police = c if (c is Node and is_instance_valid(c)) else null


func _player_pos() -> Vector3:
	if main_ref == null:
		return Vector3.ZERO
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return (a as Node3D).global_position
	var v: Variant = main_ref.get("vehicle")
	if v is Node3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return (v as Node3D).global_position
	return Vector3.ZERO


func _on_foot() -> bool:
	return main_ref != null and main_ref.get("on_foot") == true


## READ-ONLY peek at sky_weather's clock. Absent peer -> a plain noon.
func _hour() -> float:
	if _sky == null or not is_instance_valid(_sky):
		return DEFAULT_HOUR
	var t: Variant = _sky.get("time_of_day")
	return fposmod(float(t), 24.0) if (t is float or t is int) else DEFAULT_HOUR


## READ-ONLY peek at the supercell mix (0 fair .. 1 full storm). Falls back to
## the public is_storm flag if the mix is ever renamed.
func _storm() -> float:
	if _sky == null or not is_instance_valid(_sky):
		return 0.0
	var m: Variant = _sky.get("_mix")
	if m is float or m is int:
		return clampf(float(m), 0.0, 1.0)
	return 1.0 if _sky.get("is_storm") == true else 0.0


## Signed insideness: + = metres to the nearest edge from within, - = metres
## out. Used for hysteresis, so it must be smooth in both directions.
func _rect_margin(r: Rect2, x: float, z: float) -> float:
	var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	if dx > 0.0 or dz > 0.0:
		return -sqrt(dx * dx + dz * dz)
	return minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))


## A region keeps you until you are REGION_HYST metres clear of it, so walking
## the boundary cannot flip the bed back and forth.
func _pick_region(p: Vector3) -> int:
	var sdt := _rect_margin(DOWNTOWN_RECT, p.x, p.z)
	var ssb := _rect_margin(SUBURB_RECT, p.x, p.z)
	var t_dt := -REGION_HYST if _region == REG_DOWNTOWN else 0.0
	var t_sb := -REGION_HYST if _region == REG_SUBURB else 0.0
	if sdt > t_dt and sdt >= ssb:
		return REG_DOWNTOWN
	if ssb > t_sb:
		return REG_SUBURB
	return REG_PRAIRIE


## 1.0 on the deck, falling to 0 at FWY_AUDIBLE metres from the corridor.
func _freeway_prox(p: Vector3) -> float:
	var dx := maxf(absf(p.x) - FWY_HALF_LEN, 0.0)
	var dz := maxf(absf(p.z) - FWY_HALF_W, 0.0)
	var d := sqrt(dx * dx + dz * dz)
	return pow(clampf(1.0 - d / FWY_AUDIBLE, 0.0, 1.0), FWY_CURVE)


func _ramp(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


## Dawn chorus 04:36-06:00 up, full to ~07:30, a daytime murmur, a small
## pre-dusk uptick, gone by 19:30 and silent all night.
func _bird_gate(h: float) -> float:
	var day := lerpf(1.0, BIRD_DAY_FLOOR, _ramp(h, 7.5, 10.0))
	day = lerpf(day, BIRD_EVENING, _ramp(h, 16.5, 18.2))
	return _ramp(h, 4.6, 6.0) * day * (1.0 - _ramp(h, 18.0, 19.5))


## Texas cicadas start in the afternoon heat and peak at dusk; done by 22:36.
func _cicada_gate(h: float) -> float:
	var tail := 1.0 - _ramp(h, 21.2, 22.6)
	return maxf(_ramp(h, 12.5, 15.0) * CICADA_DAY, _ramp(h, 17.3, 19.2)) * tail


## Crickets take over at dusk and run to first light. Split at noon so the
## curve wraps midnight without a discontinuity.
func _cricket_gate(h: float) -> float:
	if h < 12.0:
		return 1.0 - _ramp(h, 4.8, 6.2)
	return _ramp(h, 19.4, 20.8)


## The whole city thins in the small hours: deepest at 03:00, back to normal
## by 08:00 and not yet dipped at 22:00.
func _quiet_gate(h: float) -> float:
	var d := absf(h - NIGHT_QUIET_HOUR)
	if d > 12.0:
		d = 24.0 - d
	return lerpf(NIGHT_QUIET, 1.0, clampf(d / NIGHT_QUIET_SPAN, 0.0, 1.0))


## The whole context collapsed into six numbers. Pure in its arguments, so the
## harness can drive it with synthetic weather and never touch sky_weather.
func _compute_targets(reg: int, prox: float, hour: float, storm: float, gust: float) -> void:
	var mix: Array = REGION_MIX[clampi(reg, 0, REGION_MIX.size() - 1)]
	var duck := lerpf(1.0, STORM_DUCK, storm)          # rain owns the mix
	var quiet := _quiet_gate(hour)
	var bug := duck * (1.0 - STORM_BUG_KILL * storm)   # nothing sings in a squall
	_wt[L_CITY] = float(mix[L_CITY]) * quiet * duck
	_wt[L_FREEWAY] = float(mix[L_FREEWAY]) * prox * quiet * duck
	# Wind is the one layer a storm makes LOUDER, and it breathes even fair.
	_wt[L_WIND] = clampf(float(mix[L_WIND]) * (0.55 + 0.45 * gust)
		+ storm * lerpf(STORM_WIND_LO, STORM_WIND_HI, gust), 0.0, 1.0)
	_wt[L_CICADA] = float(mix[L_CICADA]) * _cicada_gate(hour) * bug
	_wt[L_CRICKET] = float(mix[L_CRICKET]) * _cricket_gate(hour) * bug
	_wt[L_BIRD] = float(mix[L_BIRD]) * _bird_gate(hour) * bug


func _apply_filter() -> void:
	if _lp == null or absf(_muffle - _last_muffle) < 0.001:
		return
	_last_muffle = _muffle
	# Log interpolation: the sweep sounds linear to the ear as the door shuts.
	_lp.cutoff_hz = LP_OPEN_HZ * pow(LP_CAB_HZ / LP_OPEN_HZ, _muffle)


func _apply_levels() -> void:
	var trim := CAB_TRIM_DB * _muffle
	for i in LAYER_COUNT:
		var p := _players[i]
		if not is_instance_valid(p):
			continue
		var w := _w[i]
		if w <= CUT_W:
			if p.playing:
				p.stop()
				_last_db[i] = -999.0
			continue
		var db := LAYER_DB[i] + LAYER_CAB_DB[i] * _muffle + trim + linear_to_db(w)
		if absf(db - _last_db[i]) >= DB_EPSILON:
			_last_db[i] = db
			p.volume_db = db
		if not p.playing:
			p.play()


func _update_shots(delta: float) -> void:
	if _shot == null or not is_instance_valid(_shot):
		return
	_shot_t -= delta
	if _shot_t > 0.0:
		return
	_shot_t = _rng.randf_range(SHOT_MIN_S, SHOT_MAX_S)
	if _shot.playing or _storm() > SHOT_STORM_MAX:
		return
	var pool: Array = SHOT_POOL[clampi(_region, 0, SHOT_POOL.size() - 1)]
	var pick := int(pool[_rng.randi_range(0, pool.size() - 1)])
	# A far siren while you actually have heat would read as a second cruiser.
	if pick == SH_SIREN and _heat() > 0:
		return
	_shot.stream = _shot_streams[pick]
	_shot.volume_db = SHOT_DB[pick] + CAB_TRIM_DB * _muffle
	_shot.play()


func _heat() -> int:
	if _police == null or not is_instance_valid(_police):
		return 0
	var h: Variant = _police.get("heat")
	return int(h) if h is int else 0


# ============================== SYNTHESIS CORE ===============================
func _build_streams() -> void:
	_streams.resize(LAYER_COUNT)
	_streams[L_CITY] = _build_city()
	_streams[L_FREEWAY] = _build_freeway()
	_streams[L_WIND] = _build_wind()
	_streams[L_CICADA] = _build_cicada()
	_streams[L_CRICKET] = _build_cricket()
	_streams[L_BIRD] = _build_bird()
	_shot_streams.resize(SHOT_COUNT)
	_shot_streams[SH_HORN] = _build_horn()
	_shot_streams[SH_DOG] = _build_dog()
	_shot_streams[SH_TRAIN] = _build_train()
	_shot_streams[SH_SIREN] = _build_far_siren()
	_shot_streams[SH_DOOR] = _build_door()


func _zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)                     # resize zero-fills
	return b


func _noise(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = _rng.randf_range(-1.0, 1.0)
	return b


func _alpha(hz: float) -> float:
	return clampf(1.0 - exp(-TAU * hz / float(MIX_RATE)), 0.0, 1.0)


## THE SEAM KILLER. A one-pole lowpass run AROUND THE RING: it is primed on the
## END of the buffer first, so the state it starts sample 0 with is the state it
## will hold after sample n-1 — the output is genuinely periodic with the
## buffer. A noise bed filtered this way loops with no seam and no crossfade:
## nothing is faded over, because there is nothing to hide.
## The prime does not need a whole lap. A one-pole's memory decays as (1-a)^k,
## so priming over 20 time constants leaves an error of e^-20 (~2e-9) — a
## thousand times below 16-bit quantization, for a fraction of the work.
func _ring_lp(src: PackedFloat32Array, a: float) -> PackedFloat32Array:
	var n := src.size()
	var warm := mini(n, maxi(4096, int(20.0 / maxf(a, 0.0001))))
	var y := 0.0
	for k in warm:
		var j := n - warm + k
		y += a * (src[j] - y)       # prime on the tail, discarded
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		y += a * (src[i] - y)
		out[i] = y
	return out


## Circular highpass = signal minus its circular lowpass. Still periodic.
func _ring_hp(src: PackedFloat32Array, a: float) -> PackedFloat32Array:
	var lp := _ring_lp(src, a)
	var out := PackedFloat32Array()
	var n := src.size()
	out.resize(n)
	for i in n:
		out[i] = src[i] - lp[i]
	return out


## RMS normalization (not peak): noise and tones only compare honestly by
## energy, and the dB table above is only meaningful if they do. A peak cap
## catches anything that would clip on the way out.
func _normalize(buf: PackedFloat32Array, rms: float, peak_cap: float) -> void:
	var n := buf.size()
	if n == 0:
		return
	var acc := 0.0
	var pk := 0.0
	for i in n:
		var v := buf[i]
		acc += v * v
		pk = maxf(pk, absf(v))
	var cur := sqrt(acc / float(n))
	if cur < 0.000001:
		return
	var g := rms / cur
	if pk * g > peak_cap:
		g = peak_cap / maxf(pk, 0.000001)
	for i in n:
		buf[i] *= g


## Slow modulators (gusts, cicada tymbals, swells) are read from a small table
## instead of calling sin() a million times. The index is COMPUTED from i, not
## accumulated, so there is no drift and the wrap at sample n is exact: with an
## integer cycle count, i = n lands back on table index 0 by construction.
func _mod_at(i: int, n: int, cycles: int) -> int:
	return int(float(i) * float(cycles) * float(MOD_SIZE) / float(n)) & MOD_MASK


## A tonal partial placed by INTEGER CYCLE COUNT over the whole buffer: it
## closes the loop exactly, with no frequency rounding to argue about.
## hz = cycles * MIX_RATE / n.
func _drone(buf: PackedFloat32Array, cycles: int, amp: float, phase := 0.0) -> void:
	var n := buf.size()
	var k := TAU * float(cycles) / float(n)
	for i in n:
		buf[i] += amp * sin(k * float(i) + phase)


## A short windowed burst: phase-accumulated sweep hz0 -> hz1 under a raised-
## sine-squared window (dead silent at both ends), written with wrap-around so
## a burst straddling the loop point is still continuous.
func _pulse(buf: PackedFloat32Array, start: int, dur: int, hz0: float, hz1: float,
		amp: float, harm2 := 0.0) -> void:
	var n := buf.size()
	var ph := 0.0
	for i in dur:
		var t := float(i) / float(dur)
		var env := sin(PI * t)
		env *= env
		buf[posmod(start + i, n)] += (sin(ph) + harm2 * sin(ph * 2.0)) * env * amp
		ph += TAU * lerpf(hz0, hz1, t) / float(MIX_RATE)


## A raised-cosine bump added into an envelope buffer, wrapping the loop point.
func _hump(buf: PackedFloat32Array, centre: int, half: int, gain: float) -> void:
	var n := buf.size()
	for j in (half * 2):
		var t := float(j - half) / float(half)
		var w := 0.5 + 0.5 * cos(PI * t)
		buf[posmod(centre + j - half, n)] += gain * w * w


## Plain running lowpass, in place. One-shots only — they are enveloped to
## silence at both ends, so they have no seam to protect.
func _lowpass(buf: PackedFloat32Array, a: float, passes: int) -> void:
	for _p in passes:
		var y := 0.0
		for i in buf.size():
			y += a * (buf[i] - y)
			buf[i] = y


## Feedback comb — a two-cent reverb tail. Two of these at co-prime delays is
## the whole trick behind "that happened four blocks away".
func _comb(buf: PackedFloat32Array, delay: int, gain: float) -> void:
	for i in range(delay, buf.size()):
		buf[i] += buf[i - delay] * gain


func _fade_tail(buf: PackedFloat32Array, fade: int) -> void:
	var n := buf.size()
	for i in fade:
		buf[n - 1 - i] *= float(i) / float(fade)


func _wav(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	if looping:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# ============================== THE LAYERS ===================================
## CITY (8.0 s) — downtown from the sidewalk. A low traffic wash (white noise
## through three circular lowpasses, breathing twice across the loop), the
## HVAC stack on the roof behind you (61.5 and 62.5 Hz beating at exactly 1 Hz,
## a 92.25 Hz second unit, a 246 Hz fan whine — all integer cycle counts), and
## a thin band of rooftop air over the top.
func _build_city() -> AudioStreamWAV:
	var n := CITY_SAMPLES
	var wash := _ring_lp(_ring_lp(_ring_lp(_noise(n), _alpha(300.0)), _alpha(300.0)), _alpha(220.0))
	_normalize(wash, WORK_RMS, NO_CAP)
	var buf := _zeros(n)
	var k := TAU * 2.0 / float(n)   # 2 whole cycles = 0.25 Hz "traffic breathing"
	for i in n:
		buf[i] = wash[i] * (0.72 + 0.28 * sin(k * float(i))) * 0.85
	_drone(buf, 492, 0.085)         # 61.5 Hz  compressor
	_drone(buf, 500, 0.060, 1.9)    # 62.5 Hz  second unit -> 1 Hz beat
	_drone(buf, 738, 0.038, 0.7)    # 92.25 Hz
	_drone(buf, 1968, 0.014, 2.6)   # 246 Hz   fan whine
	var air := _ring_hp(_ring_lp(_noise(n), _alpha(2600.0)), _alpha(700.0))
	_normalize(air, WORK_RMS, NO_CAP)
	for i in n:
		buf[i] += air[i] * 0.16
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


## FREEWAY (9.0 s) — tire roar off the deck. Two circularly-filtered copies of
## the SAME noise (a dark 600 Hz roar and a bright 4.2 kHz tread hiss) blended
## by a passing-vehicle envelope: five raised-cosine humps that both raise the
## level and open the brightness, so each one reads as a car arriving and
## leaving rather than a fader move. Any blend of two circular signals is
## itself circular, so the loop is seamless by construction.
func _build_freeway() -> AudioStreamWAV:
	var n := FWY_SAMPLES
	var src := _noise(n)
	var dark := _ring_lp(_ring_lp(src, _alpha(900.0)), _alpha(600.0))
	var bright := _ring_hp(_ring_lp(src, _alpha(4200.0)), _alpha(700.0))
	_normalize(dark, WORK_RMS, NO_CAP)
	_normalize(bright, WORK_RMS, NO_CAP)
	var env := _zeros(n)
	for i in n:
		env[i] = FWY_FLOOR
	for k in FWY_PASSES.size():
		var pass_def: Array = FWY_PASSES[k]
		_hump(env, int(float(pass_def[0]) * float(n)),
			int(float(pass_def[1]) * float(MIX_RATE)), float(pass_def[2]))
	var buf := _zeros(n)
	for i in n:
		var e := env[i]
		var b := clampf((e - FWY_FLOOR) / 0.75, 0.0, 1.0)
		buf[i] = (dark[i] * (1.0 - 0.35 * b) + bright[i] * (0.10 + 0.55 * b)) * e
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


## WIND (10.0 s) — over grass, over a parking lot, over a levee. A broad body
## (three circular lowpasses) plus an edge hiss (circular band 600 Hz - 2.2 kHz),
## gusted by three whole-cycle sines at 0.1 / 0.2 / 0.3 Hz. The hiss rides the
## SQUARE of the gust, so lulls go soft and dark and gusts get teeth — the one
## detail that separates wind from a noise generator.
func _build_wind() -> AudioStreamWAV:
	var n := WIND_SAMPLES
	var src := _noise(n)
	var body := _ring_lp(_ring_lp(_ring_lp(src, _alpha(600.0)), _alpha(600.0)), _alpha(400.0))
	var hiss := _ring_hp(_ring_lp(src, _alpha(2200.0)), _alpha(600.0))
	_normalize(body, WORK_RMS, NO_CAP)
	_normalize(hiss, WORK_RMS, NO_CAP)
	# The gust envelope: three whole-cycle sines at 0.1 / 0.2 / 0.3 Hz, tabled
	# once (one table lookup per sample beats three sin() calls per sample).
	var t_g := PackedFloat32Array()
	t_g.resize(MOD_SIZE)
	for j in MOD_SIZE:
		var x := TAU * float(j) / float(MOD_SIZE)
		t_g[j] = clampf(0.52 + 0.26 * sin(x) + 0.14 * sin(2.0 * x + 1.7)
			+ 0.08 * sin(3.0 * x + 4.1), 0.06, 1.0)
	var buf := _zeros(n)
	for i in n:
		var g := t_g[_mod_at(i, n, 1)]
		buf[i] = body[i] * g + hiss[i] * g * g * 0.55
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


## CICADA (6.0 s) — the dry August rasp. One circular 3.4-7 kHz noise band
## serves as the carrier for all four insects (each reads it at a different
## offset, which decorrelates them for free); each is chopped by a tymbal pulse
## train at 84-102 Hz raised to the fourth power (buzzy, not sine-y) and
## breathed by its own slow swell. Every modulator is an integer cycle count
## over the loop and the carrier is circular, so the product closes exactly.
func _build_cicada() -> AudioStreamWAV:
	var n := CICADA_SAMPLES
	var carrier := _ring_hp(_ring_lp(_noise(n), _alpha(7000.0)), _alpha(3400.0))
	_normalize(carrier, WORK_RMS, NO_CAP)
	# Tymbal (raised cosine to the fourth — buzzy, not sine-y) and swell, tabled.
	var t_tym := PackedFloat32Array()
	var t_swl := PackedFloat32Array()
	t_tym.resize(MOD_SIZE)
	t_swl.resize(MOD_SIZE)
	for j in MOD_SIZE:
		var th := TAU * float(j) / float(MOD_SIZE)
		var p := 0.5 + 0.5 * cos(th)
		p = p * p
		t_tym[j] = p * p
		t_swl[j] = 0.30 + 0.70 * maxf(sin(th), 0.0)
	var buf := _zeros(n)
	for k in CICADA_VOICES.size():
		var v: Array = CICADA_VOICES[k]
		var tym := int(v[0])
		var swl := int(v[1])
		var phi := float(v[2])
		var gain := float(v[3])
		var off := int(float(n) * (0.13 + 0.21 * float(k)))
		# Index steps computed, never accumulated: i = n lands back on index 0
		# exactly (integer cycle counts), so the loop closes with no drift.
		var st_tym := float(tym) * float(MOD_SIZE) / float(n)
		var st_swl := float(swl) * float(MOD_SIZE) / float(n)
		var i_tym := int(phi / TAU * float(MOD_SIZE))
		var i_swl := int(phi * 0.7 / TAU * float(MOD_SIZE))
		for i in n:
			var fi := float(i)
			buf[i] += carrier[(i + off) % n] * gain \
				* t_tym[(int(fi * st_tym) + i_tym) & MOD_MASK] \
				* t_swl[(int(fi * st_swl) + i_swl) & MOD_MASK]
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


## CRICKET (8.0 s) — a field, not a metronome. Seven crickets, each with its
## own pitch (4.15-5.25 kHz), its own chirp rate, 3-4 pulses per chirp and its
## own loudness, so most of them are far away. Pulses are windowed to silence
## and written with wrap, so the loop point lands either in silence or inside
## a windowed pulse — click-free either way. A faint circular high band under
## everything is the hundred crickets you cannot pick out.
func _build_cricket() -> AudioStreamWAV:
	var n := CRICKET_SAMPLES
	var buf := _zeros(n)
	var pw := int(0.016 * float(MIX_RATE))
	var gap := int(0.034 * float(MIX_RATE))
	for c in CRICKET_COUNT:
		var hz := _rng.randf_range(4150.0, 5250.0)
		var reps := _rng.randi_range(9, 16)
		var period := int(float(n) / float(reps))
		var pulses := _rng.randi_range(3, 4)
		var amp := _rng.randf_range(0.18, 1.0) * 0.11
		var off := _rng.randi_range(0, n - 1)
		for r in reps:
			var base := off + r * period + _rng.randi_range(-900, 900)
			for q in pulses:
				_pulse(buf, posmod(base + q * gap, n), pw, hz, hz * 0.995, amp, 0.28)
	var carpet := _ring_hp(_ring_lp(_noise(n), _alpha(6200.0)), _alpha(3800.0))
	_normalize(carpet, WORK_RMS, NO_CAP)
	var k := TAU * 3.0 / float(n)
	for i in n:
		buf[i] += carpet[i] * (0.22 + 0.10 * sin(k * float(i))) * 0.30
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


## BIRD (12.0 s) — deliberately sparse; eleven motifs in twelve seconds and
## most of them quiet. Three shapes: a down-slurred whistle, a two-note call,
## and a fast up-chip trill, each a phase-accumulated frequency sweep under a
## raised-sine window, placed by the seeded RNG with wrap-around writes.
func _build_bird() -> AudioStreamWAV:
	var n := BIRD_SAMPLES
	var buf := _zeros(n)
	for _m in BIRD_MOTIFS:
		var kind := _rng.randi_range(0, 2)
		var root := _rng.randf_range(1900.0, 3600.0)
		var amp := _rng.randf_range(0.10, 0.55)
		var at := _rng.randi_range(0, n - 1)
		if kind == 0:                                   # down-slur
			_pulse(buf, at, int(0.16 * float(MIX_RATE)), root * 1.25, root * 0.82,
				amp * 0.50, 0.22)
		elif kind == 1:                                 # two-note call
			_pulse(buf, at, int(0.11 * float(MIX_RATE)), root, root * 1.02,
				amp * 0.50, 0.18)
			_pulse(buf, posmod(at + int(0.19 * float(MIX_RATE)), n),
				int(0.13 * float(MIX_RATE)), root * 1.34, root * 1.28, amp * 0.45, 0.18)
		else:                                           # trill
			var chips := _rng.randi_range(5, 7)
			for q in chips:
				_pulse(buf, posmod(at + q * int(0.055 * float(MIX_RATE)), n),
					int(0.032 * float(MIX_RATE)), root * 0.95, root * 1.18,
					amp * 0.42, 0.30)
	_normalize(buf, BED_RMS, BED_PEAK_CAP)
	return _wav(buf, true)


# ============================== PUNCTUATION ==================================
## Two-tone car horn, four blocks away: 370 + 466 Hz with a 1/n harmonic stack,
## lowpassed hard and thrown down a street by two combs.
func _build_horn() -> AudioStreamWAV:
	var n := 22050                  # 1.0 s
	var buf := _zeros(n)
	var hold := 9000
	for tone: float in [370.0, 466.0]:
		for h in 4:
			var hz := tone * float(h + 1)
			var amp := 0.30 / float(h + 1)
			var ph := 0.0
			var step := TAU * hz / float(MIX_RATE)
			for i in hold:
				var t := float(i) / float(hold)
				var env := minf(t * 14.0, 1.0) * minf((1.0 - t) * 9.0, 1.0)
				buf[i] += sin(ph) * env * amp
				ph += step
	_lowpass(buf, _alpha(1300.0), 2)
	_comb(buf, 3181, 0.30)
	_comb(buf, 7027, 0.22)
	_lowpass(buf, _alpha(1800.0), 1)
	_normalize(buf, 0.16, 0.80)
	_fade_tail(buf, 3000)
	return _wav(buf, false)


## A dog two yards over: three barks, each a 250 -> 170 Hz growl plus a noise
## rasp, fast attack, hard decay, then dulled and bounced off the houses.
func _build_dog() -> AudioStreamWAV:
	var n := 26460                  # 1.2 s
	var buf := _zeros(n)
	var starts: Array[int] = [0, 7500, 16800]
	var lens: Array[int] = [3100, 2800, 3400]
	var gains: Array[float] = [1.0, 0.85, 0.72]
	for k in 3:
		var at := starts[k]
		var dur := lens[k]
		var gain := gains[k]
		var ph := 0.0
		var prev := 0.0
		for i in dur:
			var t := float(i) / float(dur)
			var env := minf(t * 22.0, 1.0) * exp(-4.2 * t)
			var hz := lerpf(250.0, 170.0, t)
			var w := _rng.randf_range(-1.0, 1.0)
			var rasp := (w + prev) * 0.5
			prev = w
			buf[at + i] += (sin(ph) * 0.7 + sin(ph * 2.0) * 0.28 + rasp * 0.45) * env * gain * 0.5
			ph += TAU * hz / float(MIX_RATE)
	_lowpass(buf, _alpha(1500.0), 2)
	_comb(buf, 4409, 0.24)
	_normalize(buf, 0.14, 0.80)
	_fade_tail(buf, 2500)
	return _wav(buf, false)


## The one that makes you look up. A five-chime horn (Eb minor cluster) a mile
## out: sawish stacks, a slight per-chime detune, a 1.5% pressure droop across
## the blast, a long swell, and a heavy lowpass plus two combs for the mile.
func _build_train() -> AudioStreamWAV:
	var n := 57330                  # 2.6 s
	var buf := _zeros(n)
	var hold := 48000
	var chimes: Array[float] = [311.1, 370.0, 415.3, 466.2, 622.3]
	var detune: Array[float] = [0.0, 0.004, -0.003, 0.005, -0.002]
	# House idiom (radio.gd): the whole 5-harmonic stack lives in ONE table, so
	# each chime is a single table walk instead of five per-sample sin() calls.
	var tw := PackedFloat32Array()
	tw.resize(MOD_SIZE)
	for j in MOD_SIZE:
		var th := TAU * float(j) / float(MOD_SIZE)
		var s := 0.0
		for h in 5:
			s += sin(th * float(h + 1)) / pow(float(h + 1), 1.2)
		tw[j] = s
	for c in chimes.size():
		var base := chimes[c] * (1.0 + detune[c])
		var ph := 0.0
		for i in hold:
			var t := float(i) / float(hold)
			var env := minf(t * 4.5, 1.0) * minf((1.0 - t) * 3.0, 1.0)
			buf[i] += tw[int(ph) & MOD_MASK] * env * 0.14
			ph += float(MOD_SIZE) * base * (1.0 - 0.015 * t) / float(MIX_RATE)
	# Breath: the air the horn is actually made of.
	var prev := 0.0
	for i in hold:
		var t := float(i) / float(hold)
		var w := _rng.randf_range(-1.0, 1.0)
		buf[i] += (w + prev) * 0.5 * minf(t * 4.5, 1.0) * minf((1.0 - t) * 3.0, 1.0) * 0.10
		prev = w
	_lowpass(buf, _alpha(950.0), 2)
	_comb(buf, 5501, 0.34)
	_comb(buf, 11003, 0.26)
	_lowpass(buf, _alpha(1400.0), 1)
	_normalize(buf, 0.17, 0.80)
	_fade_tail(buf, 6000)
	return _wav(buf, false)


## Somebody else's problem, several blocks over: one slow 520 -> 760 -> 520 Hz
## wail under a long arc envelope (it arrives and it goes), heavily dulled.
## Deliberately 22 dB under the real police siren so it can never be mistaken
## for one, and suppressed entirely while you actually have heat.
func _build_far_siren() -> AudioStreamWAV:
	var n := 52920                  # 2.4 s
	var buf := _zeros(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		var tri := 2.0 * t if t < 0.5 else 2.0 * (1.0 - t)
		var hz := lerpf(520.0, 760.0, tri)
		var arc := sin(PI * t)
		buf[i] = sin(ph) * arc * arc * 0.5
		ph += TAU * hz / float(MIX_RATE)
	_lowpass(buf, _alpha(1100.0), 2)
	_comb(buf, 6151, 0.26)
	_normalize(buf, 0.13, 0.75)
	_fade_tail(buf, 4000)
	return _wav(buf, false)


## Car door across the street: a latch click and a body thunk, dulled.
func _build_door() -> AudioStreamWAV:
	var n := 11025                  # 0.5 s
	var buf := _zeros(n)
	for i in 110:                   # latch
		var t := float(i) / 110.0
		buf[i] += _rng.randf_range(-1.0, 1.0) * (1.0 - t) * (1.0 - t) * 0.6
	var ph := 0.0
	var prev := 0.0
	for i in 5200:                  # thunk
		var t := float(i) / 5200.0
		var env := minf(t * 40.0, 1.0) * exp(-9.0 * t)
		var w := _rng.randf_range(-1.0, 1.0)
		buf[900 + i] += (sin(ph) * 0.8 + (w + prev) * 0.5 * 0.35) * env
		prev = w
		ph += TAU * lerpf(105.0, 78.0, t) / float(MIX_RATE)
	_lowpass(buf, _alpha(1000.0), 2)
	_comb(buf, 2971, 0.20)
	_normalize(buf, 0.12, 0.75)
	_fade_tail(buf, 1800)
	return _wav(buf, false)
