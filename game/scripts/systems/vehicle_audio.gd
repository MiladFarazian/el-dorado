extends Node
## VEHICLE AUDIO v1 — fully procedural: engine, tire skid, police sirens, and
## impact thuds, all synthesized at setup into AudioStreamWAV buffers (16-bit
## mono 22050 Hz, built once, zero per-frame allocation). No asset files.
## ENTIRELY DISABLED in smoke mode: setup returns early, processing off.
## Players are attached lazily each physics tick (the vehicle is replaced on
## Tab and its children are wiped on tuning hot-reload, so refs are re-checked
## every frame). Siren players ride each cruiser and die with it.

# ============================== TUNABLES =====================================
const RNG_SEED := 0xAD10                   # skid/impact noise (deterministic)
const MIX_RATE := 22050                    # Hz, all buffers

# Engine loop: harmonics on a ~55 Hz base; period is an exact sample count so
# a whole number of periods loops click-free. base = 22050/400 = 55.125 Hz.
const ENGINE_PERIOD_SAMPLES := 400
const ENGINE_PERIODS := 27                 # 10800 samples ~= 0.49 s
const ENGINE_HARMONICS: Array[float] = [1.0, 0.5, 0.33]  # saw-ish 1/n rolloff
const ENGINE_GAIN := 0.45
# Pseudo-RPM: forward speed folded into 4 gear bands; pitch climbs across a
# band then drops at the shift, smoothed so a full 0.9 drop takes ~0.15 s.
const GEAR_COUNT := 4
const GEAR_WIDTH := 9.0                    # m/s of forward speed per gear band
const PITCH_LOW := 1.0
const PITCH_HIGH := 1.9
const IDLE_PITCH := 0.9
const IDLE_SPEED := 1.0                    # below this: idle pitch/volume
const SHIFT_RATE := 6.0                    # pitch units/s -> 0.9 in 0.15 s
const ENGINE_PEAK_DB := -8.0               # full throttle
const ENGINE_IDLE_DB := -26.0              # coasting / standstill
const ENGINE_UNIT_SIZE := 12.0
const ENGINE_MAX_DIST := 90.0

# Skid loop: lowpassed white noise, ~0.7 s, tail crossfaded into the head.
const SKID_SAMPLES := 15434                # ~0.7 s
const SKID_FADE := 1024                    # crossfade length (samples)
const SKID_LOWPASS_TAPS := 6               # moving-average window
const SKID_GAIN := 2.0
const SKID_SLIP_MIN := 4.5                 # m/s lateral slip to start
const SKID_SLIP_FULL := 12.0               # slip for full volume
const SKID_SPEED_MIN := 6.0                # no skid noise while crawling
const SKID_ATTACK := 8.0                   # level units/s (quick attack)
const SKID_RELEASE := 3.4                  # ~0.3 s full release
const SKID_PEAK_DB := -10.0
const SKID_UNIT_SIZE := 10.0
const SKID_MAX_DIST := 70.0

# Siren loop: two-tone wail, sine sweeping 600->900->600 Hz over 2 s. The
# discrete triangle sweep sums to exactly 1500 cycles, so the loop is seamless.
const SIREN_SAMPLES := 44100               # 2.0 s
const SIREN_LOW_HZ := 600.0
const SIREN_HIGH_HZ := 900.0
const SIREN_GAIN := 0.8
const SIREN_DB := -12.0
const SIREN_UNIT_SIZE := 18.0              # audible falloff for approach drama
const SIREN_MAX_DIST := 320.0
const SIREN_POLL_S := 0.5                  # group("police") poll cadence
const SIREN_META := "vehicle_audio_siren"  # marks cruisers already wired

# Impact one-shot: noise burst, fast exponential decay, ~0.25 s.
const IMPACT_SAMPLES := 5512
const IMPACT_DECAY := 18.0                 # exp(-t*decay)
const IMPACT_GAIN := 0.9
const IMPACT_DV_MIN := 6.0                 # m/s velocity delta in one tick
const IMPACT_DV_FULL := 20.0               # dv at/above this -> peak volume
const IMPACT_MIN_DB := -18.0
const IMPACT_PEAK_DB := -4.0
const IMPACT_COOLDOWN := 0.3
const IMPACT_UNIT_SIZE := 12.0
const IMPACT_MAX_DIST := 120.0
# --- Horn (D-056): the ambience horn's 370 + 466 Hz pair, up close, held on H.
const HORN_SAMPLES := 11025                # 0.5 s loop
const HORN_TONES: Array[float] = [370.0, 466.0]
const HORN_GAIN := 0.32
const HORN_DB := -7.0
const HORN_UNIT_SIZE := 14.0
const HORN_MAX_DIST := 180.0
const HORN_PED_RADIUS := 16.0              # walkers ahead of the grille bolt

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _engine_stream: AudioStreamWAV = null
var _skid_stream: AudioStreamWAV = null
var _siren_stream: AudioStreamWAV = null
var _impact_stream: AudioStreamWAV = null
var _horn_stream: AudioStreamWAV = null
var _horn: AudioStreamPlayer3D = null
var _engine: AudioStreamPlayer3D = null
var _skid: AudioStreamPlayer3D = null
var _impact: AudioStreamPlayer3D = null
var _engine_pitch := IDLE_PITCH
var _skid_level := 0.0
var _prev_vel := Vector3.ZERO
var _prev_vehicle_id := 0
var _impact_cd := 0.0
var _siren_poll_t := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true            # SMOKE SAFETY: no buffers, no processing
		set_physics_process(false)
		return
	_rng.seed = RNG_SEED
	_engine_stream = _build_engine_loop()
	_skid_stream = _build_skid_loop()
	_siren_stream = _build_siren_loop()
	_impact_stream = _build_impact_shot()
	_horn_stream = _build_horn_loop()


func on_vehicle_changed(_vehicle: Node) -> void:
	if _disabled:
		return
	# The old body is NOT guaranteed to be freed any more. Tab used to be the
	# only way the player vehicle changed and it freed the old rig, taking these
	# players with it; carjacking leaves the old car parked in the world, so an
	# unstopped engine loop would idle at that spot forever (audible across the
	# map, and leaked at quit). Silence and free them explicitly, then recreate
	# lazily on the new body.
	for p: Variant in [_engine, _skid, _impact, _horn]:
		if p is AudioStreamPlayer3D and is_instance_valid(p):
			(p as AudioStreamPlayer3D).stop()
			(p as AudioStreamPlayer3D).queue_free()
	_engine = null
	_skid = null
	_impact = null
	_horn = null
	_engine_pitch = IDLE_PITCH
	_skid_level = 0.0
	_prev_vehicle_id = 0


func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	_impact_cd = maxf(_impact_cd - delta, 0.0)
	_siren_poll_t -= delta
	if _siren_poll_t <= 0.0:
		_siren_poll_t = SIREN_POLL_S
		_poll_sirens()
	var veh := _vehicle()
	if veh == null:
		_prev_vehicle_id = 0
		return
	_ensure_players(veh)
	_update_engine(veh, delta)
	_update_skid(veh, delta)
	_update_impact(veh)
	_update_horn(veh)


# ============================== RUNTIME ======================================
func _vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


## The vehicle is replaced on Tab and its children are freed on tuning
## hot-reload; recreate any player that is missing or orphaned.
func _ensure_players(veh: RigidBody3D) -> void:
	if _engine == null or not is_instance_valid(_engine) or _engine.get_parent() != veh:
		_engine = _make_player(veh, _engine_stream, ENGINE_UNIT_SIZE, ENGINE_MAX_DIST, ENGINE_IDLE_DB)
		_engine.pitch_scale = _engine_pitch
		_engine.play()
	if _skid == null or not is_instance_valid(_skid) or _skid.get_parent() != veh:
		_skid = _make_player(veh, _skid_stream, SKID_UNIT_SIZE, SKID_MAX_DIST, SKID_PEAK_DB)
	if _impact == null or not is_instance_valid(_impact) or _impact.get_parent() != veh:
		_impact = _make_player(veh, _impact_stream, IMPACT_UNIT_SIZE, IMPACT_MAX_DIST, IMPACT_PEAK_DB)
	if _horn == null or not is_instance_valid(_horn) or _horn.get_parent() != veh:
		_horn = _make_player(veh, _horn_stream, HORN_UNIT_SIZE, HORN_MAX_DIST, HORN_DB)


## PUBLIC (traffic): the same horn, for a driver you are holding up (D-060).
func horn_stream() -> AudioStreamWAV:
	return _horn_stream


## H, held: the loop plays; the press edge tells the walkers ahead to move.
func _update_horn(veh: RigidBody3D) -> void:
	if _horn == null or not is_instance_valid(_horn):
		return
	var want: bool = veh.get("player_controlled") == true and main_ref.get("on_foot") != true \
		and InputMap.has_action("horn") and Input.is_action_pressed("horn")
	if want and not _horn.playing:
		_horn.play()
	elif not want and _horn.playing:
		_horn.stop()
	if want and Input.is_action_just_pressed("horn"):
		var sys: Variant = main_ref.get("systems")
		if sys is Dictionary and (sys as Dictionary).has("pedestrians"):
			var peds: Variant = (sys as Dictionary)["pedestrians"]
			if peds is Node and (peds as Node).has_method("honk_at"):
				(peds as Node).call("honk_at", veh, HORN_PED_RADIUS)


func _make_player(parent: Node, stream: AudioStreamWAV, unit: float, max_dist: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = max_dist
	p.volume_db = db
	parent.add_child(p)
	return p


func _update_engine(veh: RigidBody3D, delta: float) -> void:
	var fwd_speed := maxf(veh.linear_velocity.dot(-veh.global_transform.basis.z), 0.0)
	var target := IDLE_PITCH
	if fwd_speed > IDLE_SPEED:
		var band := clampi(int(fwd_speed / GEAR_WIDTH), 0, GEAR_COUNT - 1)
		var frac := clampf((fwd_speed - float(band) * GEAR_WIDTH) / GEAR_WIDTH, 0.0, 1.0)
		target = PITCH_LOW + (PITCH_HIGH - PITCH_LOW) * frac
	_engine_pitch = move_toward(_engine_pitch, target, SHIFT_RATE * delta)
	_engine.pitch_scale = _engine_pitch
	_engine.volume_db = lerpf(ENGINE_IDLE_DB, ENGINE_PEAK_DB, _throttle(veh))


func _throttle(veh: RigidBody3D) -> float:
	if bool(veh.get("external_input")):
		return clampf(float(veh.get("ext_throttle")), 0.0, 1.0)
	if veh.get("player_controlled") == false:
		return 0.0  # on foot: W is a walk key, the parked rig idles
	if InputMap.has_action("accelerate"):
		return Input.get_action_strength("accelerate")
	return 0.0


func _update_skid(veh: RigidBody3D, delta: float) -> void:
	var lv := veh.linear_velocity
	var slip := absf(lv.dot(veh.global_transform.basis.x))
	var target := 0.0
	if slip > SKID_SLIP_MIN and lv.length() > SKID_SPEED_MIN:
		target = clampf((slip - SKID_SLIP_MIN) / (SKID_SLIP_FULL - SKID_SLIP_MIN), 0.0, 1.0)
	var rate := SKID_ATTACK if target > _skid_level else SKID_RELEASE
	_skid_level = move_toward(_skid_level, target, rate * delta)
	if _skid_level < 0.01:
		if _skid.playing:
			_skid.stop()
	else:
		if not _skid.playing:
			_skid.play()
		_skid.volume_db = SKID_PEAK_DB + linear_to_db(_skid_level)


func _update_impact(veh: RigidBody3D) -> void:
	var vid := veh.get_instance_id()
	var dv := (veh.linear_velocity - _prev_vel).length()
	_prev_vel = veh.linear_velocity
	if vid != _prev_vehicle_id:
		_prev_vehicle_id = vid    # first frame on a new body: no baseline yet
		return
	var lrf: Variant = veh.get("last_reset_frame")
	if lrf is int and int(Engine.get_physics_frames()) - int(lrf) <= 1:
		return  # R-reset teleport zeroes velocity in place — not a crash
	if dv > IMPACT_DV_MIN and _impact_cd <= 0.0:
		_impact_cd = IMPACT_COOLDOWN
		var k := clampf((dv - IMPACT_DV_MIN) / (IMPACT_DV_FULL - IMPACT_DV_MIN), 0.0, 1.0)
		_impact.volume_db = lerpf(IMPACT_MIN_DB, IMPACT_PEAK_DB, k)
		_impact.play()
		# The same impact energy that picks the thud volume shakes the camera:
		# one source of truth for "how hard did we just hit something".
		var cam: Variant = main_ref.get("camera")
		if cam is Object and is_instance_valid(cam) and (cam as Object).has_method("add_trauma"):
			(cam as Object).call("add_trauma", 0.25 + 0.6 * k)


## A playing AudioStreamPlayer3D at engine quit leaks its stream objects in
## 4.7.1 (constant 2-object warning) — stop everything on teardown so headless
## runs exit clean.
func _exit_tree() -> void:
	for p: Variant in [_engine, _skid, _impact, _horn]:
		if p is AudioStreamPlayer3D and is_instance_valid(p):
			(p as AudioStreamPlayer3D).stop()
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("police"):
			if n is Node and is_instance_valid(n):
				for c in (n as Node).get_children():
					if c is AudioStreamPlayer3D:
						(c as AudioStreamPlayer3D).stop()


## Wire a looping siren onto every cruiser exactly once; the player node is a
## child of the cruiser, so despawn/queue_free silences it automatically.
func _poll_sirens() -> void:
	for n in get_tree().get_nodes_in_group("police"):
		if n is Node3D and is_instance_valid(n) and not n.has_meta(SIREN_META):
			n.set_meta(SIREN_META, true)
			var p := _make_player(n, _siren_stream, SIREN_UNIT_SIZE, SIREN_MAX_DIST, SIREN_DB)
			# Cruisers exit the tree (and the "police" group) before our
			# _exit_tree sweep can see them — self-stop or the playback leaks.
			p.tree_exiting.connect(p.stop)
			p.play()


# ============================== SYNTHESIS ====================================
## Sum of 3 sine harmonics (1/n amplitudes for a soft saw character) on a
## 55.125 Hz base; the loop holds whole periods of every harmonic -> no click.
func _build_engine_loop() -> AudioStreamWAV:
	var base_hz := float(MIX_RATE) / float(ENGINE_PERIOD_SAMPLES)
	var n := ENGINE_PERIOD_SAMPLES * ENGINE_PERIODS
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var ph := TAU * base_hz * float(i) / float(MIX_RATE)
		var s := 0.0
		for h in ENGINE_HARMONICS.size():
			s += ENGINE_HARMONICS[h] * sin(ph * float(h + 1))
		samples[i] = s * ENGINE_GAIN
	return _wav(samples, true)


## White noise through a moving-average lowpass; SKID_FADE extra samples are
## generated and the tail is crossfaded into the head for a seamless loop.
func _build_skid_loop() -> AudioStreamWAV:
	var total := SKID_SAMPLES + SKID_FADE
	var noise := PackedFloat32Array()
	noise.resize(total)
	for i in total:
		noise[i] = _rng.randf_range(-1.0, 1.0)
	var filtered := PackedFloat32Array()
	filtered.resize(total)
	var acc := 0.0
	for i in total:
		acc += noise[i]
		if i >= SKID_LOWPASS_TAPS:
			acc -= noise[i - SKID_LOWPASS_TAPS]
		filtered[i] = clampf(acc / float(SKID_LOWPASS_TAPS) * SKID_GAIN, -0.9, 0.9)
	var samples := PackedFloat32Array()
	samples.resize(SKID_SAMPLES)
	for i in SKID_SAMPLES:
		samples[i] = filtered[i]
	for i in SKID_FADE:
		var t := float(i) / float(SKID_FADE)
		samples[i] = filtered[i] * t + filtered[SKID_SAMPLES + i] * (1.0 - t)
	return _wav(samples, true)


## Classic wail: sine whose frequency follows a triangle 600->900->600 Hz.
## Phase is accumulated per sample; the discrete triangle sums to exactly
## (avg 750 Hz * 2 s) = 1500 whole cycles, so the loop point is click-free.
func _build_siren_loop() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(SIREN_SAMPLES)
	var phase := 0.0
	for i in SIREN_SAMPLES:
		var x := float(i) / float(SIREN_SAMPLES)
		var tri := 2.0 * x if x < 0.5 else 2.0 * (1.0 - x)
		var hz := SIREN_LOW_HZ + (SIREN_HIGH_HZ - SIREN_LOW_HZ) * tri
		samples[i] = SIREN_GAIN * sin(phase)
		phase += TAU * hz / float(MIX_RATE)
	return _wav(samples, true)


## Two-tone horn, loop-safe: each partial is rounded to a whole number of cycles
## per buffer so the seam is silent; a one-pole lowpass keeps it a honk, not a buzz.
func _build_horn_loop() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(HORN_SAMPLES)
	for tone: float in HORN_TONES:
		for h in 3:
			var cycles := roundf(tone * float(h + 1) * float(HORN_SAMPLES) / float(MIX_RATE))
			var step := TAU * cycles / float(HORN_SAMPLES)
			var amp := HORN_GAIN / float(h + 1)
			for i in HORN_SAMPLES:
				samples[i] += sin(step * float(i)) * amp
	var y := 0.0
	for i in HORN_SAMPLES:
		y += 0.32 * (samples[i] - y)
		samples[i] = y
	return _wav(samples, true)


## Noise burst with a fast exponential decay (short ramp-in kills the DC pop;
## light lowpass makes it a thud rather than a hiss).
func _build_impact_shot() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(IMPACT_SAMPLES)
	var n0 := 0.0
	var n1 := 0.0
	var n2 := 0.0
	var n3 := 0.0
	for i in IMPACT_SAMPLES:
		n3 = n2
		n2 = n1
		n1 = n0
		n0 = _rng.randf_range(-1.0, 1.0)
		var t := float(i) / float(MIX_RATE)
		var attack := minf(float(i) / 16.0, 1.0)
		samples[i] = (n0 + n1 + n2 + n3) * 0.25 * exp(-IMPACT_DECAY * t) * attack * IMPACT_GAIN
	return _wav(samples, false)


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
