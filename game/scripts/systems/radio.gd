extends Node
## RADIO v1 — the in-car dial. Five stations off the canon ten (naming-bible
## §9) + OFF, cycled with "radio_next" (N). Every bed is synthesized at setup
## into a seamless AudioStreamWAV loop (16-bit mono 22050 Hz): notes are
## rendered onto a fixed tempo grid with WRAP-AROUND tails (an event that runs
## past the buffer end continues at sample 0), so the loop point is inaudible
## by construction. Beds differ in real musical structure — walking bass vs
## 808 grid vs oom-pah vs beatless pads — not just timbre.
## Station switch: ~0.25 s of band static, a short per-station ID stinger,
## then the bed. OFF is a static blip into silence.
## Active ONLY while driving; leaving the car fades out fast and the SAME
## station resumes on re-entry (session-persistent, no save integration yet).
## ENTIRELY INERT in smoke mode. Patterns are consts for v1; the ten-station
## JSON pattern pipeline is backlog.

# ============================== TUNABLES =====================================
const RNG_SEED := 0xD1A1                   # deterministic noise/bell placement
const MIX_RATE := 22050                    # Hz, all buffers
const ACTION := "radio_next"               # main.gd binds N; we guard + fallback

# The whole radio sits well under the engine (peak -8 dB): beds normalize to
# 0.62 (-4.2 dBFS) on a -20 dB player -> ~-24 dBFS, ducked at full throttle,
# present at cruise. Nothing here may mask the police siren (-12 dB).
const RADIO_DB := -20.0
const FADE_IN_S := 0.2                     # re-entry fade up
const FADE_OUT_S := 0.3                    # leaving the car fades out fast
const STATIC_S := 0.25                     # band static between stations
const FLASH_S := 2.5                       # HUD station card lifetime
const FLASH_FADE_S := 0.8                  # tail of the card fade

const BED_PEAK := 0.62
const STINGER_PEAK := 0.5
const STATIC_PEAK := 0.45

const WT_SIZE := 256                       # wavetable resolution (power of 2)
const WT_MASK := 255

# The five most tonally distinct of the canon dial, in cycle order.
# [canon name, one-line tagline in canon voice]
const STATIONS: Array = [
	["RED DIRT REVIVAL 89.3", "Waylon Estes spins songs about leavin', for everybody who stayed"],
	["GRIND 105.7 (KGRN)", "Slabs up, windows down — the Trill Association holds the aux"],
	["LA JEFA 104.5", "La única que te dice cómo está el tráfico DE VERDAD"],
	["99.9 THE SINGULARITY", "DJ Skye composed this for you 0.4 seconds before you wanted it"],
	["MEGAPLEX PUBLIC RADIO (KMPX)", "Day 214 of the spring pledge drive — we can hear your dial hand"],
]

# Tempo grids: beat lengths are exact sample counts so bar math stays integer.
const RD_BEAT := 13781                     # ~96 BPM  — Red Dirt Revival
const GR_BEAT := 18375                     # 72 BPM   — Grind (half-time trap)
const LJ_BEAT := 13230                     # 100 BPM  — La Jefa (norteño 2-beat)

# Switch/playback state machine. Harness note: ST_BED == 3.
enum { ST_OFF, ST_STATIC, ST_STINGER, ST_BED }

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _player: AudioStreamPlayer = null      # ONE non-positional player, never freed
var _beds: Array[AudioStreamWAV] = []
var _stingers: Array[AudioStreamWAV] = []
var _static: AudioStreamWAV = null
var _station := -1                         # -1 = OFF; 0..4 index into STATIONS
var _state := ST_OFF
var _timer := 0.0                          # static/stinger countdown
var _fade := 0.0                           # 0..1 gain factor on RADIO_DB
var _ui: CanvasLayer = null
var _flash_name: Label = null
var _flash_tag: Label = null
var _flash_t := 0.0
# Wavetables (built once; every tone is a table walk, not per-sample sin()).
var _t_sine: PackedFloat32Array
var _t_soft: PackedFloat32Array
var _t_bass: PackedFloat32Array
var _t_sub: PackedFloat32Array
var _t_pluck: PackedFloat32Array
var _t_reed: PackedFloat32Array
var _t_string: PackedFloat32Array
var _t_bell: PackedFloat32Array


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true            # SMOKE SAFETY: no buffers, no processing
		set_physics_process(false)
		set_process(false)
		return
	set_process(false)              # physics tick only
	# main.gd owns the binding; register a fallback so the dial works either way.
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_N
		InputMap.action_add_event(ACTION, ev)
	_rng.seed = RNG_SEED
	_build_all_streams()
	_player = AudioStreamPlayer.new()  # non-positional: it's the cab speaker
	_player.volume_db = RADIO_DB
	# AUDIO LAW (4.7.1 leaks playing streams at quit): self-stop on tree exit.
	_player.tree_exiting.connect(_player.stop)
	add_child(_player)
	_build_ui()


func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	var driving := _driving()
	if driving and InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION):
		_cycle()
	if driving:
		if _state == ST_STATIC or _state == ST_STINGER:
			_timer -= delta
			if _timer <= 0.0:
				_advance()
		elif _state == ST_BED and _station >= 0 and not _player.playing:
			_play_stream(_beds[_station])   # re-entry: SAME station resumes
	# Fade: every audible state wants full gain while driving; leaving the car
	# (or the OFF blip ending) ramps to silence, then the player fully stops.
	var want := driving and _state != ST_OFF
	var rate := (1.0 / FADE_IN_S) if want else (1.0 / FADE_OUT_S)
	_fade = move_toward(_fade, 1.0 if want else 0.0, rate * delta)
	if _fade <= 0.0:
		if _player.playing:
			_player.stop()
			if _station >= 0:
				_state = ST_BED     # abandoned mid-intro: come back to the bed
	else:
		_player.volume_db = RADIO_DB + linear_to_db(_fade)
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		var a := clampf(_flash_t / FLASH_FADE_S, 0.0, 1.0)
		_flash_name.modulate.a = a
		_flash_tag.modulate.a = a
		if _flash_t <= 0.0:
			_flash_name.visible = false
			_flash_tag.visible = false


## AUDIO LAW: a playing stream at engine quit leaks in 4.7.1 — stop on teardown.
func _exit_tree() -> void:
	if _player != null and is_instance_valid(_player):
		_player.stop()


# ============================== RUNTIME ======================================
func _driving() -> bool:
	if main_ref == null or main_ref.get("on_foot") == true:
		return false
	var v: Variant = main_ref.get("vehicle")
	return v != null and is_instance_valid(v) and v is RigidBody3D \
		and (v as Node).is_inside_tree()


func _cycle() -> void:
	_station = -1 if _station >= STATIONS.size() - 1 else _station + 1
	_state = ST_STATIC
	_timer = STATIC_S
	_fade = 1.0                     # the dial clicks in at full radio volume
	_play_stream(_static)
	if _station >= 0:
		var st: Array = STATIONS[_station]
		_flash(String(st[0]), String(st[1]))
	else:
		_flash("RADIO OFF", "")


func _advance() -> void:
	if _state == ST_STATIC:
		if _station < 0:
			_state = ST_OFF         # OFF = static blip, then silence
			_player.stop()
		else:
			_state = ST_STINGER
			_timer = _stream_len(_stingers[_station])
			_play_stream(_stingers[_station])
	elif _state == ST_STINGER:
		_state = ST_BED
		_play_stream(_beds[_station])


func _play_stream(s: AudioStreamWAV) -> void:
	_player.stream = s
	_player.volume_db = RADIO_DB + linear_to_db(maxf(_fade, 0.001))
	_player.play()


func _stream_len(s: AudioStreamWAV) -> float:
	return float(s.data.size()) * 0.5 / float(MIX_RATE)


# ============================== UI ===========================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 9                   # above race (8), under police HUD (12)
	add_child(_ui)
	var box := VBoxContainer.new()  # assigned slot: top-center, y ~170
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 170)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_ui.add_child(box)
	_flash_name = _make_label(34, Color(1.0, 0.83, 0.36))
	box.add_child(_flash_name)
	_flash_tag = _make_label(19, Color(0.93, 0.9, 0.84))
	box.add_child(_flash_tag)


func _make_label(pt: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", pt)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE    # HUD law: every Control
	l.visible = false
	return l


func _flash(title: String, tag: String) -> void:
	if _flash_name == null:
		return
	_flash_name.text = title
	_flash_tag.text = tag
	_flash_name.visible = true
	_flash_tag.visible = tag != ""
	_flash_name.modulate.a = 1.0
	_flash_tag.modulate.a = 1.0
	_flash_t = FLASH_S


# ============================== SYNTHESIS CORE ===============================
func _build_all_streams() -> void:
	_t_sine = _make_table([1.0])
	_t_soft = _make_table([1.0, 0.3, 0.1])
	_t_bass = _make_table([1.0, 0.4, 0.15])
	_t_sub = _make_table([1.0, 0.12])
	_t_pluck = _make_table([1.0, 0.55, 0.32, 0.18, 0.1])
	_t_reed = _make_table([1.0, 0.15, 0.55, 0.1, 0.35, 0.05, 0.2])  # odd-rich reed
	_t_string = _make_table([1.0, 0.5, 0.33, 0.25, 0.2, 0.16])      # saw-ish
	_t_bell = _make_table([1.0, 0.0, 0.25, 0.0, 0.08])
	_static = _build_static()
	_beds.append(_build_red_dirt())
	_beds.append(_build_grind())
	_beds.append(_build_jefa())
	_beds.append(_build_singularity())
	_beds.append(_build_kmpx())
	_stingers.append(_build_stinger_red_dirt())
	_stingers.append(_build_stinger_grind())
	_stingers.append(_build_stinger_jefa())
	_stingers.append(_build_stinger_singularity())
	_stingers.append(_build_stinger_kmpx())


func _make_table(harmonics: Array) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(WT_SIZE)
	for i in WT_SIZE:
		var s := 0.0
		for h in harmonics.size():
			s += float(harmonics[h]) * sin(TAU * float(h + 1) * float(i) / float(WT_SIZE))
		t[i] = s
	return t


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


func _zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)                     # resize zero-fills
	return b


## Plucked/struck tone: wavetable walk under an exponential decay, optional
## detuned second voice (chorus/twang). Writes wrap past the buffer end so
## looping beds stay seamless; one-shots must simply fit their buffer.
func _add_tone(buf: PackedFloat32Array, start: int, dur: int, hz: float, amp: float,
		decay: float, table: PackedFloat32Array, detune := 0.0, attack := 48) -> void:
	var n := buf.size()
	var step := float(WT_SIZE) * hz / float(MIX_RATE)
	var step2 := step * (1.0 + detune)
	var k := exp(-decay / float(MIX_RATE))
	var env := 1.0
	var ph := 0.0
	var ph2 := 0.0
	var two := detune > 0.0
	for i in dur:
		var a := env * amp * minf(float(i) / float(attack), 1.0)
		var s := table[int(ph) & WT_MASK]
		if two:
			s = (s + table[int(ph2) & WT_MASK]) * 0.5
			ph2 += step2
		buf[(start + i) % n] += s * a
		ph += step
		env *= k


## Sustained tone: detuned pair under a linear attack/release trapezoid — the
## beating between the pair is the "motion" (no per-sample LFO math).
func _add_sustain(buf: PackedFloat32Array, start: int, dur: int, hz: float, amp: float,
		atk: int, rel: int, table: PackedFloat32Array, detune: float) -> void:
	var n := buf.size()
	var step := float(WT_SIZE) * hz / float(MIX_RATE)
	var step2 := step * (1.0 + detune)
	var ph := 0.0
	var ph2 := 0.0
	for i in dur:
		var a := amp * minf(minf(float(i) / float(atk), float(dur - i) / float(rel)), 1.0)
		var s := (table[int(ph) & WT_MASK] + table[int(ph2) & WT_MASK]) * 0.5
		buf[(start + i) % n] += s * a
		ph += step
		ph2 += step2


## Percussive noise: hp=true differentiates (hats/scrapers), else 2-tap lowpass
## (brush snare/claps). Deterministic via the seeded system RNG.
func _add_noise(buf: PackedFloat32Array, start: int, dur: int, amp: float,
		decay: float, hp: bool) -> void:
	var n := buf.size()
	var k := exp(-decay / float(MIX_RATE))
	var env := 1.0
	var prev := 0.0
	for i in dur:
		var w := _rng.randf_range(-1.0, 1.0)
		var s := (w - prev) * 0.7 if hp else (w + prev) * 0.5
		prev = w
		buf[(start + i) % n] += s * env * amp * minf(float(i) / 8.0, 1.0)
		env *= k


## 808-style kick: phase-accumulated sine sweeping hz0 -> hz1 over the first
## third of the hit, exponential decay, short ramp-in against the DC pop.
func _add_kick(buf: PackedFloat32Array, start: int, dur: int, hz0: float, hz1: float,
		amp: float, decay: float) -> void:
	var n := buf.size()
	var k := exp(-decay / float(MIX_RATE))
	var env := 1.0
	var ph := 0.0
	for i in dur:
		var t := minf(float(i) / (float(dur) * 0.35), 1.0)
		buf[(start + i) % n] += env * amp * minf(float(i) / 24.0, 1.0) * sin(ph)
		ph += TAU * lerpf(hz0, hz1, t) / float(MIX_RATE)
		env *= k


func _normalize(buf: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for i in buf.size():
		m = maxf(m, absf(buf[i]))
	if m > 0.0001:
		var g := peak / m
		for i in buf.size():
			buf[i] *= g


## One-shots end on a forced fade so a truncated decay tail can never click.
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


# ============================== THE BEDS =====================================
## RED DIRT REVIVAL 89.3 — country/red-dirt, ~96 BPM, 4 bars of 4/4 in G
## (~10.0 s). Walking quarter-note bass over G-C-D-G, twang-detuned pentatonic
## picking on the eighths, brush snare on 2 & 4, train-chug tick on offbeats.
func _build_red_dirt() -> AudioStreamWAV:
	var n := RD_BEAT * 16
	var buf := _zeros(n)
	var bass: Array = [43, 47, 50, 48, 48, 52, 55, 50, 50, 54, 57, 45, 43, 47, 50, 47]
	for b in 16:
		_add_tone(buf, b * RD_BEAT, int(RD_BEAT * 1.5), _hz(int(bass[b])), 0.30, 3.5, _t_bass)
	var pick: Array = [
		67, -1, 62, 64, 67, -1, 64, 62,
		64, -1, 60, 64, 67, -1, 69, 67,
		66, -1, 62, 66, 69, -1, 66, 62,
		67, -1, 62, 64, 59, 62, 64, 67]
	var eighth := int(RD_BEAT / 2.0)
	for s8 in 32:
		var m := int(pick[s8])
		if m >= 0:
			_add_tone(buf, s8 * eighth, RD_BEAT, _hz(m), 0.15, 5.5, _t_pluck, 0.004)
	for b in 16:
		if b % 2 == 1:              # brush snare on 2 & 4
			_add_noise(buf, b * RD_BEAT, 3300, 0.10, 22.0, false)
		_add_noise(buf, b * RD_BEAT + eighth, 900, 0.045, 60.0, true)
	_normalize(buf, BED_PEAK)
	return _wav(buf, true)


## GRIND 105.7 (KGRN) — slab/trap, 72 BPM half-time, 4 bars (~13.3 s) in C
## minor. 808 kicks on a 16th grid (busier bar 4), snare on 3, closed hats
## with end-of-bar rolls, whole-bar sub notes C-C-Eb-G, pumping dark Cm pad.
func _build_grind() -> AudioStreamWAV:
	var n := GR_BEAT * 16
	var buf := _zeros(n)
	var s16 := float(GR_BEAT) / 4.0
	var subs: Array = [36, 36, 39, 31]
	for bar in 4:
		var b0 := bar * GR_BEAT * 4
		var kicks: Array = [0, 6, 10] if bar != 3 else [0, 3, 6, 10, 14]
		for kk: int in kicks:
			_add_kick(buf, b0 + int(s16 * float(kk)), 6000, 90.0, 38.0, 0.50, 12.0)
		_add_noise(buf, b0 + int(s16 * 8.0), 3600, 0.22, 18.0, false)   # snare
		_add_tone(buf, b0 + int(s16 * 8.0), 2400, 190.0, 0.10, 25.0, _t_sine)
		for h in 8:
			_add_noise(buf, b0 + int(s16 * float(h) * 2.0), 1100, 0.055, 90.0, true)
		if bar == 1 or bar == 3:    # 16th hat roll into the next bar
			for r in 4:
				_add_noise(buf, b0 + int(s16 * float(12 + r)), 900, 0.05, 110.0, true)
		_add_sustain(buf, b0 + 200, GR_BEAT * 4 - 4000, _hz(int(subs[bar])), 0.26, 300, 3000, _t_sub, 0.001)
		for v: int in [48, 51, 55]: # Cm pad, re-swelling each bar (sidechain feel)
			_add_sustain(buf, b0, GR_BEAT * 4, _hz(v), 0.04, 9000, 9000, _t_soft, 0.004)
	_normalize(buf, BED_PEAK)
	return _wav(buf, true)


## LA JEFA 104.5 — norteño/cumbia, 100 BPM, 4 bars (~9.6 s) in G. Tuba-ish
## root-fifth on 1 & 3, wet detuned accordion triads stabbing the offbeats,
## güira scraper ticking the eighths. Pure oom-pah engine.
func _build_jefa() -> AudioStreamWAV:
	var n := LJ_BEAT * 16
	var buf := _zeros(n)
	var tuba: Array = [[43, 38], [36, 43], [38, 45], [43, 38]]
	var stabs: Array = [[55, 59, 62], [55, 60, 64], [54, 57, 62], [55, 59, 62]]
	for bar in 4:
		var b0 := bar * LJ_BEAT * 4
		var roots: Array = tuba[bar]
		_add_tone(buf, b0, 9000, _hz(int(roots[0])), 0.34, 5.0, _t_bass, 0.0, 140)
		_add_tone(buf, b0 + LJ_BEAT * 2, 9000, _hz(int(roots[1])), 0.34, 5.0, _t_bass, 0.0, 140)
		var chord: Array = stabs[bar]
		for beat: int in [1, 3]:
			for m: int in chord:
				_add_tone(buf, b0 + LJ_BEAT * beat, 6000, _hz(m), 0.075, 9.0, _t_reed, 0.006)
		for e in 8:
			var acc := 0.055 if e % 2 == 0 else 0.038
			_add_noise(buf, b0 + int(float(LJ_BEAT) * 0.5 * float(e)), 1400, acc, 40.0, true)
	_normalize(buf, BED_PEAK)
	return _wav(buf, true)


## 99.9 THE SINGULARITY — beatless late-night ambient (12.0 s). Three chord
## pads (Am9 / Fmaj7 / Em7add9) crossfading in thirds and wrapping the seam,
## a slow-breathing 55 Hz sub, and six long pentatonic bell notes scattered
## by the seeded RNG. Slightly too perfect, the way Skye likes it.
func _build_singularity() -> AudioStreamWAV:
	var n := 264600
	var buf := _zeros(n)
	var seg := 88200
	var half := int(float(n) / 2.0)
	var chords: Array = [[45, 48, 52, 59], [41, 45, 48, 52], [40, 47, 50, 54]]
	for c in 3:
		var chord: Array = chords[c]
		for m: int in chord:
			_add_sustain(buf, c * seg, seg + 22050, _hz(m), 0.055, 22050, 22050, _t_soft, 0.004)
	_add_sustain(buf, 0, half + 20000, 55.0, 0.07, 30000, 30000, _t_sine, 0.002)
	_add_sustain(buf, half, half + 20000, 55.0, 0.07, 30000, 30000, _t_sine, 0.002)
	var bells: Array = [69, 76, 72, 79, 83, 74]
	for b in 6:
		_add_tone(buf, _rng.randi_range(0, n - 1), 60000, _hz(int(bells[b])), 0.09, 1.6, _t_bell, 0.003)
	_normalize(buf, BED_PEAK)
	return _wav(buf, true)


## MEGAPLEX PUBLIC RADIO (KMPX) — easy classical (12.0 s): C - Am - F - G,
## 3 s per chord. Detuned string-section sustains, a cello root an octave
## down, and a slow flute line floating one note per half-bar over the top.
func _build_kmpx() -> AudioStreamWAV:
	var n := 264600
	var buf := _zeros(n)
	var seg := 66150
	var chords: Array = [[48, 52, 55, 60], [45, 48, 52, 57], [41, 45, 48, 53], [43, 47, 50, 55]]
	var cellos: Array = [36, 33, 29, 31]
	for c in 4:
		var chord: Array = chords[c]
		for m: int in chord:
			_add_sustain(buf, c * seg, seg + 8000, _hz(m), 0.05, 9000, 12000, _t_string, 0.005)
		_add_sustain(buf, c * seg, seg + 6000, _hz(int(cellos[c])), 0.09, 6000, 9000, _t_bass, 0.003)
	var mel: Array = [64, 67, 69, 67, 65, 64, 62, 59]
	var mdur := 33075
	for i in 8:
		_add_sustain(buf, i * mdur, 30000, _hz(int(mel[i])), 0.085, 3000, 8000, _t_soft, 0.002)
	_normalize(buf, BED_PEAK)
	return _wav(buf, true)


# ============================== STATIC & STINGERS ============================
## Band static between stations: differentiated white noise with a stepped
## amplitude flutter (the "searching the dial" crackle), edges faded.
func _build_static() -> AudioStreamWAV:
	var nsam := 5512               # 0.25 s
	var buf := _zeros(nsam)
	var prev := 0.0
	var flutter := 1.0
	for i in nsam:
		if i % 480 == 0:
			flutter = _rng.randf_range(0.45, 1.0)
		var w := _rng.randf_range(-1.0, 1.0)
		buf[i] = (w - prev * 0.6) * flutter
		prev = w
	for i in 64:
		var g := float(i) / 64.0
		buf[i] *= g
		buf[nsam - 1 - i] *= g
	_normalize(buf, STATIC_PEAK)
	return _wav(buf, false)


## Station IDs: 2-4 notes each, unmistakably that station's instrument.
func _build_stinger_red_dirt() -> AudioStreamWAV:
	var buf := _zeros(22050)       # three ascending twang plucks: G3 D4 G4
	_add_tone(buf, 0, 20000, _hz(55), 0.4, 3.0, _t_pluck, 0.004)
	_add_tone(buf, 5500, 16000, _hz(62), 0.4, 3.0, _t_pluck, 0.004)
	_add_tone(buf, 11000, 11000, _hz(67), 0.45, 3.0, _t_pluck, 0.004)
	_normalize(buf, STINGER_PEAK)
	_fade_tail(buf, 2500)
	return _wav(buf, false)


func _build_stinger_grind() -> AudioStreamWAV:
	var buf := _zeros(19845)       # 808 boom, Eb2 -> C2 sub drop, two hat ticks
	_add_kick(buf, 0, 6000, 90.0, 36.0, 0.6, 10.0)
	_add_tone(buf, 2000, 9000, _hz(39), 0.3, 4.0, _t_sub)
	_add_tone(buf, 9000, 10000, _hz(36), 0.35, 4.0, _t_sub)
	_add_noise(buf, 4500, 900, 0.15, 90.0, true)
	_add_noise(buf, 9000, 900, 0.15, 90.0, true)
	_normalize(buf, STINGER_PEAK)
	_fade_tail(buf, 2500)
	return _wav(buf, false)


func _build_stinger_jefa() -> AudioStreamWAV:
	var buf := _zeros(16538)       # accordion roll G4 B4 D5 over a tuba G2
	_add_tone(buf, 0, 16000, _hz(43), 0.35, 4.0, _t_bass, 0.0, 140)
	_add_tone(buf, 0, 9000, _hz(67), 0.3, 5.0, _t_reed, 0.006)
	_add_tone(buf, 3000, 9000, _hz(71), 0.3, 5.0, _t_reed, 0.006)
	_add_tone(buf, 6000, 10000, _hz(74), 0.33, 5.0, _t_reed, 0.006)
	_normalize(buf, STINGER_PEAK)
	_fade_tail(buf, 2000)
	return _wav(buf, false)


func _build_stinger_singularity() -> AudioStreamWAV:
	var buf := _zeros(22050)       # pure whole-tone chime: A4 B4 C#5 — synthetic
	_add_tone(buf, 0, 20000, _hz(69), 0.32, 2.2, _t_bell)
	_add_tone(buf, 4400, 15000, _hz(71), 0.32, 2.2, _t_bell)
	_add_tone(buf, 8800, 13000, _hz(73), 0.36, 2.2, _t_bell)
	_normalize(buf, STINGER_PEAK)
	_fade_tail(buf, 2500)
	return _wav(buf, false)


func _build_stinger_kmpx() -> AudioStreamWAV:
	var buf := _zeros(24255)       # soft C-major string swell into a G5 chime
	for m: int in [60, 64, 67]:
		_add_sustain(buf, 0, 18000, _hz(m), 0.22, 5000, 9000, _t_string, 0.005)
	_add_tone(buf, 10000, 14000, _hz(79), 0.3, 2.0, _t_bell)
	_normalize(buf, STINGER_PEAK)
	_fade_tail(buf, 2500)
	return _wav(buf, false)
