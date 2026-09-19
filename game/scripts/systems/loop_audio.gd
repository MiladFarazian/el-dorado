extends Node
## LOOP AUDIO v1 — the core loop's voice. The LONGHORN push, the close, the
## debtor bolting, Boone's showroom bell and his repo chain, the note drafting,
## and rank. Eleven one-shot cues, every one SYNTHESISED AT SETUP into an
## AudioStreamWAV (16-bit mono 22050 Hz) and cached; no asset files, no
## per-frame synthesis, no per-frame allocation. Tunables in
## data/mechanics/loop_audio.json.
##
## TWO non-positional players (these are phone/UI sounds, not world sounds):
## `_player` carries ten cues, `_alt` carries "rankup" alone — rank increments
## on the SAME frame the delivery closes, and one player cannot say both.
##
## Peers are all optional and read through main.systems: repo_orders
## (order_pushed / order_closed, plus polled `state` and `rank`) and dealer
## (vehicle_granted / vehicle_repossessed, plus polled note paid/missed
## counts). Wiring happens on the first physics tick, NOT in setup —
## main.gd's _load_systems calls setup in alphabetical order and repo_orders
## sorts after loop_audio, so it does not exist yet when we are set up.
##
## AUDIO LAW (D-023/D-106, 4.7.1 leaks playing streams at quit): both players
## self-stop on tree_exiting, _exit_tree stops them again, nulls their streams
## and drops the cache — the eleven AudioStreamWAV are RefCounted and die with
## it, so the live-stream count at quit does not grow by this system.
## ENTIRELY INERT in smoke mode.

# ============================== TUNABLES =====================================
const DATA_PATH := "res://data/mechanics/loop_audio.json"
const MIX_RATE_DEF := 22050
const RNG_SEED_DEF := 46609
const PEAK_DEF := 0.55
const DB_DEF := -12.0
const FLEEING := 3                 # repo_orders.State.FLEEING (polled, no signal)
const WT_SIZE := 256               # wavetable resolution (power of two)
const WT_MASK := 255
const ATTACK := 48                 # default ramp-in samples; kills the DC pop
const FADE_TAIL := 220             # forced tail fade: a cut decay can never click
const CUES: Array[String] = [
	"push", "push_bad", "delivered", "voided", "expired",
	"run", "bell", "chain", "coin", "buzz", "rankup",
]
# Struck metal: inharmonic partials with per-partial decays (the high ones die
# first, which is the whole reason a bell sounds like a bell).
const BELL_PARTIAL: Array[float] = [1.0, 2.76, 5.40, 8.93]
const BELL_AMP: Array[float] = [1.0, 0.46, 0.26, 0.13]
const BELL_DECAY: Array[float] = [1.5, 2.6, 4.2, 7.0]

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _cfg: Dictionary = {}
var _rate := MIX_RATE_DEF
var _streams: Dictionary = {}      # cue name -> AudioStreamWAV (built once)
var _player: AudioStreamPlayer = null
var _alt: AudioStreamPlayer = null
var _orders: Node = null
var _dealer: Node = null
var _wired := false
var _prev_state := -1
var _prev_rank := -1
var _note_t := 0.0
var _note_poll := 1.0
var _notes_seen: Dictionary = {}   # note path -> Vector2i(paid, missed)
var _t_sine: PackedFloat32Array
var _t_soft: PackedFloat32Array
var _t_bright: PackedFloat32Array
var _t_reed: PackedFloat32Array


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true           # SMOKE SAFETY: no buffers, no processing
		set_physics_process(false)
		set_process(false)
		return
	set_process(false)             # physics tick only
	_cfg = _load_cfg()
	_rate = int(_cfg.get("mix_rate", MIX_RATE_DEF))
	_note_poll = float(_cfg.get("note_poll_seconds", 1.0))
	_note_t = _note_poll
	_rng.seed = int(_cfg.get("rng_seed", RNG_SEED_DEF))
	_build_tables()
	_build_all()
	_player = _make_player()
	_alt = _make_player()


func _load_cfg() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {}
	var txt := FileAccess.get_file_as_string(DATA_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


## AUDIO LAW: self-stop on tree exit, belt and braces with _exit_tree.
func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = DB_DEF
	p.tree_exiting.connect(p.stop)
	add_child(p)
	return p


# ============================== RUNTIME ======================================
func _physics_process(delta: float) -> void:
	if _disabled:
		return
	if not _wired:
		_wire_peers()              # systems after us alphabetically exist by now
	if _orders != null and is_instance_valid(_orders):
		var st := _int_of(_orders, "state", _prev_state)
		if st != _prev_state:
			if st == FLEEING:
				play("run")        # he is gone — engine crank and a tyre chirp
			_prev_state = st
		var rk := _int_of(_orders, "rank", _prev_rank)
		if rk > _prev_rank:
			play("rankup")
		_prev_rank = rk
	_note_t -= delta
	if _note_t <= 0.0:
		_note_t = _note_poll
		_poll_notes()


## First-tick wiring: baselines are read BEFORE any compare so a boot cannot
## fire a phantom rank-up or a phantom flee.
func _wire_peers() -> void:
	_wired = true
	_orders = _peer("repo_orders")
	_dealer = _peer("dealer")
	if _orders != null:
		_prev_state = _int_of(_orders, "state", 0)
		_prev_rank = _int_of(_orders, "rank", 0)
		if _orders.has_signal("order_pushed"):
			_orders.connect("order_pushed", _on_pushed)
		if _orders.has_signal("order_closed"):
			_orders.connect("order_closed", _on_closed)
	if _dealer != null:
		if _dealer.has_signal("vehicle_granted"):
			_dealer.connect("vehicle_granted", _on_granted)
		if _dealer.has_signal("vehicle_repossessed"):
			_dealer.connect("vehicle_repossessed", _on_repossessed)
		_poll_notes()              # seed the paid/missed baseline, silently


func _on_pushed(bad: bool) -> void:
	play("push_bad" if bad else "push")


func _on_closed(outcome: String) -> void:
	if outcome == "delivered":
		play("delivered")
	elif outcome == "voided":
		play("voided")
	else:
		play("expired")


func _on_granted(_path: String) -> void:
	play("bell")


func _on_repossessed(_path: String) -> void:
	play("chain")


## dealer.notes has no signal, so watch each note's paid/missed counters. A
## draft day that both pays one note and misses another gets the buzz: bad news
## is the news. Baselines are per-path, so a freshly signed note (paid 0) never
## fires, and a note LONGHORN takes away is pruned rather than counted.
func _poll_notes() -> void:
	if _dealer == null or not is_instance_valid(_dealer):
		return
	var v: Variant = _dealer.get("notes")
	if not (v is Array):
		return
	var notes: Array = v
	var seeded := not _notes_seen.is_empty()
	var coin := false
	var buzz := false
	for entry: Variant in notes:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var key := String(d.get("path", ""))
		var paid := int(d.get("paid", 0))
		var missed := int(d.get("missed", 0))
		var prev: Variant = _notes_seen.get(key)
		if seeded and prev is Vector2i:
			var was: Vector2i = prev
			coin = coin or paid > was.x
			buzz = buzz or missed > was.y
		_notes_seen[key] = Vector2i(paid, missed)
	if _notes_seen.size() > notes.size():
		_prune_notes(notes)
	if buzz:
		play("buzz")
	elif coin:
		play("coin")


## Only ever runs on the tick a note leaves the array (paid off or taken).
func _prune_notes(notes: Array) -> void:
	var live := PackedStringArray()
	for entry: Variant in notes:
		if entry is Dictionary:
			live.append(String((entry as Dictionary).get("path", "")))
	for key: Variant in _notes_seen.keys():
		if not live.has(String(key)):
			_notes_seen.erase(key)


# ============================== PUBLIC =======================================
## Play a named cue. Returns false if the name is unknown or audio is inert
## (smoke mode), so a probe can assert on it.
func play(cue_name: String) -> bool:
	if _disabled or not _streams.has(cue_name):
		return false
	var p := _alt if cue_name == "rankup" else _player
	if p == null or not is_instance_valid(p):
		return false
	p.stream = _streams[cue_name]
	p.volume_db = _db_for(cue_name)
	p.play()
	return true


func cue_names() -> Array[String]:
	return CUES.duplicate()


## Seconds of audio in a cue, for a probe that wants to wait one out.
func cue_seconds(cue_name: String) -> float:
	if not _streams.has(cue_name):
		return 0.0
	var w: AudioStreamWAV = _streams[cue_name]
	return float(w.data.size()) * 0.5 / float(_rate)


## AUDIO LAW (D-023/D-106): stop, unhook the streams, drop the cache.
func _exit_tree() -> void:
	for p: Variant in [_player, _alt]:
		if p is AudioStreamPlayer and is_instance_valid(p):
			var ap: AudioStreamPlayer = p
			ap.stop()
			ap.stream = null
	_streams.clear()


# ============================== PLUMBING =====================================
func _peer(key: String) -> Node:
	if main_ref == null:
		return null
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary):
		return null
	var d: Dictionary = sys
	if not d.has(key):
		return null
	var n: Variant = d[key]
	return n if n is Node and is_instance_valid(n) else null


func _int_of(node: Node, prop: String, fallback: int) -> int:
	var v: Variant = node.get(prop)
	return int(v) if v is int or v is float else fallback


func _sub(key: String) -> Dictionary:
	var v: Variant = _cfg.get(key)
	return v if v is Dictionary else {}


func _db_for(cue_name: String) -> float:
	return float(_sub("levels_db").get(cue_name, DB_DEF))


func _peak_for(cue_name: String) -> float:
	var fallback: float = float(_cfg.get("peak", PEAK_DEF))
	return float(_sub("peaks").get(cue_name, fallback))


## Buffer length in samples for a named cue.
func _len(cue_name: String, fallback: float) -> int:
	return maxi(int(float(_rate) * float(_sub("seconds").get(cue_name, fallback))), 64)


func _note_cfg(key: String, fallback: Variant) -> Variant:
	return _sub("notes").get(key, fallback)


func _note_hz(key: String, idx: int, fallback: float) -> float:
	var v: Variant = _note_cfg(key, null)
	if v is Array and (v as Array).size() > idx:
		return float((v as Array)[idx])
	return fallback


func _midi_list(key: String, fallback: Array) -> Array:
	var v: Variant = _note_cfg(key, fallback)
	return v if v is Array else fallback


# ============================== SYNTHESIS CORE ===============================
## Every cue is a ONE-SHOT: nothing here loops, so the seam problem is a tail
## problem — _finish normalises then force-fades the last samples to zero.
func _build_tables() -> void:
	_t_sine = _table([1.0])                                    # bell partials
	_t_soft = _table([1.0, 0.32, 0.10, 0.04])                  # the corporate chime
	_t_bright = _table([1.0, 0.0, 0.40, 0.0, 0.20, 0.0, 0.10]) # odd-only: hollow, coin-ish
	_t_reed = _table([1.0, 0.58, 0.36, 0.22, 0.13])            # saw-ish: the fanfare


func _table(harmonics: Array) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(WT_SIZE)
	for i in WT_SIZE:
		var s := 0.0
		for h in harmonics.size():
			s += float(harmonics[h]) * sin(TAU * float(h + 1) * float(i) / float(WT_SIZE))
		t[i] = s
	return t


func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)                    # resize zero-fills
	return b


## Struck/plucked tone: a wavetable walk under an exponential decay, with an
## optional detuned twin for chorus. Writes are clamped to the buffer.
func _tone(buf: PackedFloat32Array, start: int, dur: int, hz: float, amp: float,
		decay: float, table: PackedFloat32Array, detune := 0.0, attack := ATTACK) -> void:
	var count := mini(dur, buf.size() - start)
	if count <= 0 or start < 0:
		return
	var step := float(WT_SIZE) * hz / float(_rate)
	var step2 := step * (1.0 + detune)
	var k := exp(-decay / float(_rate))
	var env := 1.0
	var ph := 0.0
	var ph2 := 0.0
	var two := detune > 0.0
	for i in count:
		var a := env * amp * minf(float(i) / float(attack), 1.0)
		var s := table[int(ph) & WT_MASK]
		if two:
			s = (s + table[int(ph2) & WT_MASK]) * 0.5
			ph2 += step2
		buf[start + i] += s * a
		ph += step
		env *= k


## Percussive noise: hp=true differentiates (chinks, chain slaps), else a 2-tap
## lowpass (body, thuds). Deterministic via the seeded RNG.
func _noise(buf: PackedFloat32Array, start: int, dur: int, amp: float,
		decay: float, hp: bool) -> void:
	var count := mini(dur, buf.size() - start)
	if count <= 0 or start < 0:
		return
	var k := exp(-decay / float(_rate))
	var env := 1.0
	var prev := 0.0
	for i in count:
		var w := _rng.randf_range(-1.0, 1.0)
		var s := (w - prev) * 0.7 if hp else (w + prev) * 0.5
		prev = w
		buf[start + i] += s * env * amp * minf(float(i) / 8.0, 1.0)
		env *= k


## Phase-accumulated pitch sweep hz0 -> hz1 (never a per-sample sin(TAU*hz*t),
## which steps the phase and buzzes). The engine crank and the void thud.
func _sweep(buf: PackedFloat32Array, start: int, dur: int, hz0: float, hz1: float,
		amp: float, decay: float, curve := 1.0) -> void:
	var count := mini(dur, buf.size() - start)
	if count <= 0 or start < 0:
		return
	var k := exp(-decay / float(_rate))
	var env := 1.0
	var ph := 0.0
	for i in count:
		var t := pow(float(i) / float(count), curve)
		buf[start + i] += env * amp * minf(float(i) / 24.0, 1.0) * sin(ph)
		ph += TAU * lerpf(hz0, hz1, t) / float(_rate)
		env *= k


## Tyre chirp: white noise through a 6-tap moving average (a rush, not a hiss)
## under a fast rise and an exponential fall — rubber breaking loose, then grip.
func _tyre(buf: PackedFloat32Array, start: int, dur: int, amp: float) -> void:
	var count := mini(dur, buf.size() - start)
	if count <= 0 or start < 0:
		return
	var taps := _zeros(6)
	var acc := 0.0
	var ix := 0
	for i in count:
		var w := _rng.randf_range(-1.0, 1.0)
		acc += w - taps[ix]
		taps[ix] = w
		ix = (ix + 1) % 6
		var t := float(i) / float(count)
		var env := (t / 0.14) if t < 0.14 else exp(-5.0 * (t - 0.14))
		buf[start + i] += acc / 6.0 * env * amp


func _lowpass(buf: PackedFloat32Array, k: float) -> void:
	var y := 0.0
	for i in buf.size():
		y += k * (buf[i] - y)
		buf[i] = y


func _normalize(buf: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for i in buf.size():
		m = maxf(m, absf(buf[i]))
	if m > 0.0001:
		var g := peak / m
		for i in buf.size():
			buf[i] *= g


## Normalise to the cue's peak, then force the tail to zero: a decay cut off by
## the end of the buffer would otherwise click on every play.
func _finish(buf: PackedFloat32Array, cue_name: String) -> AudioStreamWAV:
	_normalize(buf, _peak_for(cue_name))
	var fade := mini(FADE_TAIL, int(buf.size() / 4))
	var n := buf.size()
	for i in fade:
		buf[n - 1 - i] *= float(i) / float(fade)
	return _wav(buf)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = _rate
	w.stereo = false
	w.data = bytes
	return w                       # no loop_mode: every cue is a one-shot


# ============================== THE CUES =====================================
func _build_all() -> void:
	_streams["push"] = _build_push(0, "push")
	_streams["push_bad"] = _build_push(int(_note_cfg("push_bad_flat", 1)), "push_bad")
	_streams["delivered"] = _build_delivered()
	_streams["voided"] = _build_voided()
	_streams["expired"] = _build_expired()
	_streams["run"] = _build_run()
	_streams["bell"] = _build_bell()
	_streams["chain"] = _build_chain()
	_streams["coin"] = _build_coin()
	_streams["buzz"] = _build_buzz()
	_streams["rankup"] = _build_rankup()


func _push_gap() -> int:
	return int(float(_rate) * float(_note_cfg("push_gap_seconds", 0.14)))


## THE APP PUSH — two notes a perfect fifth apart, soft square under a sine,
## fast decay. `flat` semitones off the second note is the bad-paper variant:
## a fifth becomes a tritone. Nobody names it; the phone confirms it.
func _build_push(flat: int, cue_name: String) -> AudioStreamWAV:
	var buf := _zeros(_len("push", 0.35))
	var root := float(_note_cfg("push_root_midi", 81))
	var up := float(_note_cfg("push_interval", 7))
	_push_notes(buf, 0, root, up - float(flat))
	return _finish(buf, cue_name)


## The push's two notes, written at `at` — reused verbatim by the repo chain,
## which is the joke: the same tones that offered you the truck take it back.
func _push_notes(buf: PackedFloat32Array, at: int, root: float, up: float) -> void:
	var gap := _push_gap()
	_tone(buf, at, buf.size(), _hz(root), 0.50, 11.0, _t_soft)
	_tone(buf, at + gap, buf.size(), _hz(root + up), 0.50, 9.0, _t_soft)


## ORDER CLOSED / delivered — a bright register chink, then E5-B5-E6 rising.
## The loop's one payoff, and the only cue allowed above -12 dB.
func _build_delivered() -> AudioStreamWAV:
	var n := _len("delivered", 0.70)
	var buf := _zeros(n)
	_noise(buf, 0, int(float(_rate) * 0.06), 0.42, 58.0, true)
	var midi: Array = _midi_list("delivered_midi", [76, 83, 88])
	var step := int(float(_rate) * 0.11)
	for i in midi.size():
		var at := i * step
		_tone(buf, at, n - at, _hz(float(midi[i])), 0.40, 5.2, _t_bright, 0.003)
	return _finish(buf, "delivered")


## ORDER CLOSED / voided — one low thud, short tail. A sine falling 120 -> 52 Hz
## with a lowpassed noise body: the sound of paper being put down.
func _build_voided() -> AudioStreamWAV:
	var n := _len("voided", 0.45)
	var buf := _zeros(n)
	_sweep(buf, 0, n, _note_hz("voided_hz", 0, 120.0), _note_hz("voided_hz", 1, 52.0),
		0.80, 9.0, 0.45)
	_noise(buf, 0, int(float(_rate) * 0.09), 0.30, 26.0, false)
	return _finish(buf, "voided")


## ORDER CLOSED / expired — the push's two notes REVERSED (E6 down to A5) and
## dulled: a slow attack and a one-pole lowpass take the corporate shine off.
## A miss should sound small, not dramatic.
func _build_expired() -> AudioStreamWAV:
	var n := _len("expired", 0.45)
	var buf := _zeros(n)
	var root := float(_note_cfg("push_root_midi", 81))
	var up := float(_note_cfg("push_interval", 7))
	var gap := _push_gap()
	_tone(buf, 0, n, _hz(root + up), 0.45, 7.5, _t_soft, 0.0, 420)
	_tone(buf, gap, n - gap, _hz(root), 0.45, 6.0, _t_soft, 0.0, 420)
	_lowpass(buf, 0.25)
	return _finish(buf, "expired")


## THE DEBTOR RUNS (polled state -> FLEEING) — a crank sweeping 58 -> 186 Hz
## across the whole cue with the tyre chirp landing a third of the way in.
## No siren: the police get to be the only siren in this game.
func _build_run() -> AudioStreamWAV:
	var n := _len("run", 0.60)
	var buf := _zeros(n)
	_sweep(buf, 0, n, _note_hz("run_hz", 0, 58.0), _note_hz("run_hz", 1, 186.0),
		0.70, 2.2, 0.7)
	var at := int(float(n) * 0.30)
	_tyre(buf, at, n - at, 0.65)
	return _finish(buf, "run")


## BOONE / vehicle_granted — the showroom bell. Four INHARMONIC partials on a
## 660 Hz strike, each with its own decay so the top dies first, plus a 4 ms
## hammer chink. Long tail: Wade wants you to hear it across the lot.
func _build_bell() -> AudioStreamWAV:
	var n := _len("bell", 1.60)
	var buf := _zeros(n)
	var base := float(_note_cfg("bell_hz", 660.0))
	for i in BELL_PARTIAL.size():
		_tone(buf, 0, n, base * BELL_PARTIAL[i], 0.40 * BELL_AMP[i],
			BELL_DECAY[i], _t_sine, 0.002, 12)
	_noise(buf, 0, int(float(_rate) * 0.004), 0.30, 200.0, true)
	return _finish(buf, "bell")


## BOONE / vehicle_repossessed — a 12 Hz chain rattle for 0.8 s (short
## high-passed slaps at drifting amplitude), then the push's two notes. The app
## takes the truck back in the same voice it used to offer it.
func _build_chain() -> AudioStreamWAV:
	var n := _len("chain", 1.15)
	var buf := _zeros(n)
	var cfg := _sub("chain")
	var rattle := float(cfg.get("burst_seconds", 0.8))
	var hz := maxf(float(cfg.get("bursts_hz", 12.0)), 1.0)
	var step := int(float(_rate) / hz)
	var count := int(rattle * hz)
	for k in count:
		var amp := _rng.randf_range(0.32, 0.70)
		_noise(buf, k * step, int(float(step) * 0.55), amp, 70.0, true)
	_push_notes(buf, int(rattle * float(_rate)),
		float(_note_cfg("push_root_midi", 81)), float(_note_cfg("push_interval", 7)))
	return _finish(buf, "chain")


## A NOTE IS PAID (polled) — a soft coin drop: two high odd-harmonic pings and
## a lighter bounce 90 ms later. Quiet on purpose; paying Boone is not a win.
func _build_coin() -> AudioStreamWAV:
	var n := _len("coin", 0.28)
	var buf := _zeros(n)
	var midi: Array = _midi_list("coin_midi", [96, 103])
	_tone(buf, 0, n, _hz(float(midi[0])), 0.45, 38.0, _t_bright, 0.0, 12)
	_tone(buf, 0, n, _hz(float(midi[1])), 0.26, 46.0, _t_bright, 0.0, 12)
	var at := int(float(_rate) * 0.09)
	_tone(buf, at, n - at, _hz(float(midi[0])), 0.22, 55.0, _t_bright, 0.0, 12)
	return _finish(buf, "coin")


## A NOTE IS MISSED (polled) — a flat buzz. A clipped 110 Hz square under a
## square envelope: no decay, no musicality, no comfort. 20 ms edge ramps only.
func _build_buzz() -> AudioStreamWAV:
	var n := _len("buzz", 0.30)
	var buf := _zeros(n)
	var hz := float(_note_cfg("buzz_hz", 110.0))
	var edge := int(float(_rate) * 0.02)
	var ph := 0.0
	for i in n:
		var env := minf(minf(float(i) / float(edge), float(n - i) / float(edge)), 1.0)
		buf[i] = clampf(3.0 * sin(ph), -1.0, 1.0) * 0.45 * env
		ph += TAU * hz / float(_rate)
	return _finish(buf, "buzz")


## RANK UP (polled) — four notes, G major to the octave, 0.9 s. A promotion at
## LONGHORN is a push notification, not a parade: it is over before you park.
func _build_rankup() -> AudioStreamWAV:
	var n := _len("rankup", 0.90)
	var buf := _zeros(n)
	var midi: Array = _midi_list("rankup_midi", [67, 71, 74, 79])
	var step := int(float(_rate) * 0.15)
	for i in midi.size():
		var at := i * step
		var amp := 0.38 if i < midi.size() - 1 else 0.50
		_tone(buf, at, n - at, _hz(float(midi[i])), amp, 4.4, _t_reed, 0.004)
	return _finish(buf, "rankup")
