extends Node
## SAVE / LOAD — session persistence v1 for EL DORADO GRANDE.
## Snapshots the two-meter economy (repo_board money + respect), the floodway
## sprint session best (race_event._best, INF = "no best yet"), and total
## playtime to a versioned JSON file in user://. Autosaves every 20 s and on
## _exit_tree (fires on window close and quit). Writes atomically: serialize to
## a .tmp file first, then DirAccess.rename over the real name so a crash
## mid-write can never leave a truncated save behind. ENTIRELY INERT in smoke
## mode — no file I/O, no processing, nothing. Corrupt / missing /
## wrong-version files start fresh without crashing and are never deleted.
## Restoration is deferred a few physics frames so every peer system exists and
## has finished building its UI before values are pushed + signals re-emitted.
## No UI: the optional bottom-left "SAVED" ghost label (left 14, top -140) was
## skipped — the debug HUD's controls cheat-sheet (6 lines @ 15 px + panel
## margins, anchored 16 px off the bottom-left corner) reaches to roughly
## y -158, so a label at top -140 would sit inside it.

# ============================== TUNABLES =====================================
const SAVE_DIR := "user://"
const SAVE_NAME := "el_dorado_save.json"
const TMP_NAME := "el_dorado_save.json.tmp"
const SAVE_PATH := SAVE_DIR + SAVE_NAME
const TMP_PATH := SAVE_DIR + TMP_NAME
const SAVE_VERSION := 1
const AUTOSAVE_SECONDS := 20.0
const RESTORE_DELAY_FRAMES := 5      # physics frames before restoring peers

# ============================== STATE ========================================
var main_ref: Node = null
var playtime := 0.0                  # lifetime seconds: loaded + this session
var _smoke := false
var _pending: Dictionary = {}        # validated payload awaiting restoration
var _has_pending := false
var _restored := false               # restoration attempted (fresh OR loaded)
var _restore_countdown := RESTORE_DELAY_FRAMES
var _autosave_left := AUTOSAVE_SECONDS


func setup(main: Node) -> void:
	main_ref = main
	if main.get("smoke_mode") == true or OS.get_cmdline_user_args().has("--session-test"):
		_smoke = true
		set_physics_process(false)
		set_process(false)
		return
	set_process(false)               # no UI to animate; physics tick only
	_read_save()


func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	playtime += delta
	if not _restored:                # let every peer finish setup + UI first
		_restore_countdown -= 1
		if _restore_countdown <= 0:
			_apply_pending()
		return
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_SECONDS
		_write_save()


func _exit_tree() -> void:           # fires on window close and on quit
	if _smoke or not _restored:      # never clobber a real save with boot zeros
		return
	_write_save()


# ============================== PUBLIC API ===================================
func save_now() -> void:
	if _smoke or not _restored:
		return
	_write_save()


## Debugging aid (NOT bound to any key): delete the save + zero live values.
func wipe() -> void:
	if _smoke:
		return
	playtime = 0.0
	_pending = {}
	_has_pending = false
	_autosave_left = AUTOSAVE_SECONDS
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		if dir.file_exists(SAVE_NAME):
			dir.remove(SAVE_NAME)
		if dir.file_exists(TMP_NAME):
			dir.remove(TMP_NAME)
	var rb := _peer("repo_board")
	if rb != null:
		rb.set("money", 0)
		rb.set("respect", 0)
		if rb.has_signal("money_changed"):
			rb.emit_signal("money_changed", 0)
		if rb.has_signal("respect_changed"):
			rb.emit_signal("respect_changed", 0)
	var race := _peer("race_event")
	if race != null:
		race.set("_best", INF)       # race_event's "no session best" sentinel


# ============================== LOAD =========================================
func _read_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return                       # first run: fresh start, silently
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("save_load: cannot read %s (err %d) — starting fresh"
			% [SAVE_PATH, FileAccess.get_open_error()])
		return
	var text := f.get_as_text()
	f.close()
	# Instance API, not JSON.parse_string: the static helper pushes an engine
	# ERROR on malformed input, and corrupt saves must stay silent (warn only).
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_warning("save_load: corrupt save %s — starting fresh (file kept)" % SAVE_PATH)
		return
	var d := json.data as Dictionary
	if int(_num(d.get("version"), -1.0)) != SAVE_VERSION:
		push_warning("save_load: save version %s != %d — starting fresh (file kept)"
			% [str(d.get("version")), SAVE_VERSION])
		return
	_pending = d
	_has_pending = true


func _apply_pending() -> void:
	_restored = true                 # fresh or loaded: autosaves may start now
	if not _has_pending:
		return
	playtime += maxf(0.0, _num(_pending.get("playtime"), 0.0))
	var money := int(_num(_pending.get("money"), 0.0))
	var respect := int(_num(_pending.get("respect"), 0.0))
	var rb := _peer("repo_board")
	if rb != null:
		rb.set("money", money)
		rb.set("respect", respect)
		if rb.has_signal("money_changed"):   # panels listen to these
			rb.emit_signal("money_changed", money)
		if rb.has_signal("respect_changed"):
			rb.emit_signal("respect_changed", respect)
	var best: Variant = _pending.get("race_best")
	if best is float or best is int:         # JSON null = no best: keep INF
		var b := float(best)
		if is_finite(b) and b > 0.0:
			var race := _peer("race_event")
			if race != null:
				race.set("_best", b) # session-best finish time (INF when unset)
	_pending = {}
	_has_pending = false


# ============================== SAVE =========================================
func _snapshot() -> Dictionary:
	var d := {
		"version": SAVE_VERSION,
		"playtime": playtime,
		"money": 0,
		"respect": 0,
		"race_best": null,
	}
	var rb := _peer("repo_board")
	if rb != null:
		d["money"] = int(_num(rb.get("money"), 0.0))
		d["respect"] = int(_num(rb.get("respect"), 0.0))
	var race := _peer("race_event")
	if race != null:
		var b: Variant = race.get("_best")
		if (b is float or b is int) and is_finite(float(b)) and float(b) > 0.0:
			d["race_best"] = float(b)
	return d


func _write_save() -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save_load: cannot write %s (err %d)"
			% [TMP_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(_snapshot(), "", true))
	f.close()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		push_warning("save_load: cannot open %s to finalize save" % SAVE_DIR)
		return
	var err := dir.rename(TMP_NAME, SAVE_NAME)
	if err != OK and dir.file_exists(SAVE_NAME):
		# Some platforms refuse rename-over-existing: drop the old file, retry.
		dir.remove(SAVE_NAME)
		err = dir.rename(TMP_NAME, SAVE_NAME)
	if err != OK:
		push_warning("save_load: rename %s -> %s failed (err %d)"
			% [TMP_NAME, SAVE_NAME, err])


# ============================== HELPERS ======================================
func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null


func _num(v: Variant, def: float) -> float:
	return float(v) if (v is float or v is int) else def
