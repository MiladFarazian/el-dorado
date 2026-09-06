extends RefCounted
## SIGN KIT (M22) — the one place in this project where text meets a panel.
##
## WHY THIS EXISTS. Every sign in the game is a `Label3D`, and Godot 4.7's
## Label3D has NO text-overrun, no auto-shrink and no ellipsis: whatever you
## ask for is what gets drawn, straight off the edge of the board if it does
## not fit. Eleven files therefore each carried their own copy of a fitting
## heuristic:
##
##     font_size = max_w / (chars * 0.66 * pixel_size)
##
## **The 0.66 was an estimate and it is wrong.** Measured off the actual font
## (`ThemeDB.fallback_font` is **Open Sans SemiBold**; see the M22 report), the
## mean uppercase advance is 0.6458 em — but the per-STRING advance is what
## matters, and it ranges from 0.53 to 0.95:
##
##     YOU BLEED. WE BILL.  0.5295      LONGHORN DYNAMICS  0.6612
##     CATTLEMAN'S TRUST    0.5882      SLEDGEHAMMER       0.6767
##     COUNTY GENERAL       0.6307      CANDYLAND          0.6800
##     HOLLERBURGER         0.6492      OMNIMIND           0.6925
##     MIDDLINGTON          0.6536      DOWNTOWN DORADO    0.7287
##                                      (a word of Ms and Ws)  0.95
##
## A single constant cannot describe that. 0.66 clipped the wide names — the
## freeway's most-repeated destination, DOWNTOWN DORADO, ran 10 % past every
## gantry board it was on — while starving the narrow ones of 25 % of the size
## they could have had. So the constant is retired. This kit **measures the
## actual string** with the actual font and solves for the largest size that
## fits, which is exact, costs nothing at runtime (build-time only), and can
## never be wrong for a name nobody predicted.
##
## THE SECOND JOB: PERSONALITY, WITH ZERO ASSET FILES. The project ships no
## font files, so every sign in the world was the same typeface at different
## sizes — a hand-painted ghost sign, a bank lobby plaque, a stadium marquee
## and a construction hoarding all rendered as the same label. `FontVariation`
## fixes that without an asset: layered over the built-in font it gives real,
## metric-true **tracking** (`spacing_glyph`) and real synthetic **weight**
## (`variation_embolden`), plus an oblique via `variation_transform`. Measured:
## tracking moves the string width by exactly `(chars - 1) x spacing`, and
## embolden by a few percent — both of which this kit's solver accounts for, so
## personality never costs correctness.
##
## STYLES are the vocabulary. Each is a weight + tracking + oblique + an
## outline-to-size RATIO (the old code used absolute outlines, so a 12 pt blade
## sign carried a 12 px outline — an outline as thick as the stroke, which
## turns small type into a black smear).
##
## COST. One `FontVariation` per style, built once, shared by every label using
## it: eleven resources for the whole city. `FLAT` uses the bare font and
## allocates nothing.

const REF := 100.0                  # reference size for linear metric extraction
const LINE_BOX := 1.37              # font height / font_size, measured
const CAP := 0.714                  # cap height / font_size, Open Sans
## Uppercase ink is not centred in the line box: the box reserves descender
## space below the baseline that all-caps copy never uses, so the letters sit
## 0.028 em low on their panel. Label3D.offset is in font px, +Y is up.
const CAP_LIFT := 0.028
## The most of an em a style may spend on letter-spacing. Above this size the
## style's absolute tracking applies as authored; below it, tracking shrinks
## with the type so no style carries a width floor. (0.12 em is generous — real
## wide-set channel lettering runs 0.08-0.15.)
const TRACK_CAP := 0.12

enum {
	FLAT,       # no variation — texture-grade small copy, tags, plates
	GANTRY,     # highway guide sign: open, even, engineered to be read at speed
	CHANNEL,    # rooftop channel letters: heavy, wide-set, built to be seen from 2 km
	PLAQUE,     # corporate lobby: light, luxuriously tracked, small, discreet
	MARQUEE,    # stadium / church monument: heavy, tight, civic self-importance
	HOARDING,   # billboard + construction hoarding: bold, tight, shouting
	GHOST,      # faded hand-painted wall ad: oblique, loose, no outline
	STENCIL,    # municipal / utility / flood-control: light, wide, small
	HANDPAINT,  # graffiti and road copy: oblique, slightly loose
	BLADE,      # street-name blade: condensed-feeling, tight, tall for its board
	FASCIA,     # strip-mall storefront: bold, mild tracking, lit at night
}

## [track px, embolden, oblique, outline ratio, outline min, outline max]
const STYLE: Dictionary = {
	FLAT:      [0.0,   0.00,  0.00, 0.055, 1.0,  8.0],
	GANTRY:    [2.0,   0.00,  0.00, 0.045, 2.0,  6.0],
	CHANNEL:   [14.0,  1.10,  0.00, 0.070, 4.0, 26.0],
	PLAQUE:    [7.0,  -0.30,  0.00, 0.030, 1.0,  4.0],
	MARQUEE:   [-1.0,  1.30,  0.00, 0.060, 3.0, 18.0],
	HOARDING:  [-2.0,  0.80,  0.00, 0.055, 2.0, 14.0],
	GHOST:     [5.0,   0.20, -0.16, 0.000, 0.0,  0.0],
	STENCIL:   [4.0,  -0.15,  0.00, 0.040, 1.0,  5.0],
	HANDPAINT: [1.0,   0.30, -0.10, 0.050, 2.0, 10.0],
	BLADE:     [-1.0,  0.55,  0.00, 0.050, 2.0,  6.0],
	FASCIA:    [1.0,   0.70,  0.00, 0.060, 2.0, 12.0],
}

## One FontVariation per style, shared. `mesh_kit` already proves a static
## resource cache is safe under the ObjectDB-at-exit gate.
static var _fonts: Dictionary = {}
static var _plain: Dictionary = {}          # same styles, tracking stripped
static var _audit_on := -1                  # -1 unknown, 0 off, 1 on


# ============================== PUBLIC =======================================
## Build a fitted, styled Label3D. `max_w` is the REAL board width in metres
## (pass the panel's width, not a guess); `max_h` is its height, or 0 for
## unconstrained. `cap` is the largest size the art direction wants — the fit
## only ever shrinks below it.
static func make(text: String, style: int, col: Color, max_w: float,
		max_h: float, cap_size: int, pixel_size := 0.01) -> Label3D:
	var lbl := Label3D.new()
	lbl.double_sided = false          # D-016: cull the mirrored back face
	lbl.text = text
	lbl.pixel_size = pixel_size
	var fs := fit_size(text, style, max_w, max_h, cap_size, pixel_size)
	lbl.font_size = fs
	var s: Array = STYLE[style]
	if style != FLAT:
		lbl.font = _font(style, _track(style, fs))
	lbl.outline_size = int(clampf(float(s[3]) * float(fs), float(s[4]), float(s[5])))
	lbl.modulate = col
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	# Sit the caps on the panel's optical centre, not the line box's.
	if not _has_descender(text):
		lbl.offset = Vector2(0.0, CAP_LIFT * float(fs))
	_audit(text, style, fs, max_w, max_h, pixel_size)
	return lbl


## The largest font_size at which `text` fits `max_w` x `max_h` metres in this
## style, INCLUDING its outline. Never returns more than `cap_size`.
static func fit_size(text: String, style: int, max_w: float, max_h: float,
		cap_size: int, pixel_size := 0.01) -> int:
	var lines := text.split("\n")
	var longest := ""
	for l in lines:
		if l.length() > longest.length():
			longest = l
	if longest.is_empty():
		return maxi(cap_size, 1)
	var s: Array = STYLE[style]
	var track := float(s[0])
	var out_r := float(s[3])
	var budget := max_w / pixel_size                       # in font px
	# Width model, exact for this engine: the bare-font run scales linearly
	# with size, tracking is an ABSOLUTE per-gap pixel amount that does not,
	# and the outline dilates the run by its size on each side.
	var a0: float = _plain_font(style).get_string_size(
		longest, HORIZONTAL_ALIGNMENT_LEFT, -1, int(REF)).x / REF
	var gaps := float(longest.length() - 1)
	# Two regimes, because tracking is absolute and the size is not. Above the
	# TRACK_CAP knee the style's tracking applies as written; below it the
	# tracking is proportional, which is what stops a wide-set style from
	# having a WIDTH FLOOR no font size can get under (CHANNEL's 14 px over a
	# ten-gap word is 1.4 m of pure air at any size, and on a 1.55 m board that
	# overflowed at font_size 4 — caught by the in-engine audit).
	var big := (budget - gaps * track - 2.0 * float(s[4])) \
		/ maxf(a0 + 2.0 * out_r, 0.0001)
	var small := budget / maxf(a0 + TRACK_CAP * gaps + 2.0 * out_r, 0.0001)
	var fs := int(maxf(big, small))
	fs = mini(fs, cap_size)
	# Height: all-caps copy only needs its cap height; anything with a
	# descender needs the full line box.
	if max_h > 0.0:
		var per := (LINE_BOX if _has_descender(text) else CAP + 0.06)
		fs = mini(fs, int(max_h / (float(lines.size()) * per * pixel_size)))
	fs = maxi(fs, 4)
	# Verify against the REAL styled font and walk down if the model was
	# optimistic (it can be by a pixel where the outline clamp bites).
	while fs > 4:
		var f: Font = _font(style, _track(style, fs))
		var w: float = f.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs).x
		var out := clampf(out_r * float(fs), float(s[4]), float(s[5]))
		if (w + 2.0 * out) * pixel_size <= max_w:
			break
		fs -= 1
	return fs


## Break `text` onto up to `max_lines` lines at the most balanced space, so a
## long canon name on a tall narrow board (a blade sign, a hoarding, a monument
## marquee) can be set at a size somebody can actually read instead of being
## squeezed to 12 pt on a board a metre tall. Returns `text` unchanged if it is
## short enough, has no spaces, or is already broken by hand.
static func balance(text: String, max_lines := 2) -> String:
	if max_lines < 2 or text.contains("\n") or not text.contains(" "):
		return text
	var words := text.split(" ", false)
	if words.size() < 2:
		return text
	var lines := mini(max_lines, words.size())
	var target := float(text.length()) / float(lines)
	# Greedy fill to the target width, then hand the remainder to the next line.
	var out: PackedStringArray = []
	var cur := ""
	for i in words.size():
		var w: String = words[i]
		var left := words.size() - i
		if cur.is_empty():
			cur = w
		elif out.size() < lines - 1 and float(cur.length() + 1 + w.length()) > target \
				and left <= lines - out.size() - 1 + words.size():
			out.append(cur)
			cur = w
		else:
			cur += " " + w
	if not cur.is_empty():
		out.append(cur)
	while out.size() > lines:                        # never exceed the budget
		out[out.size() - 2] = out[out.size() - 2] + " " + out[out.size() - 1]
		out.remove_at(out.size() - 1)
	# Never strand a separator at the end of a line: "FEED ·" over "SEED ·
	# COAL" is a break no sign painter has ever made. Push it down instead.
	for i in range(out.size() - 1):
		var parts := out[i].rsplit(" ", true, 1)
		if parts.size() == 2 and (parts[1] == "·" or parts[1] == "&" \
				or parts[1] == "-" or parts[1] == "+"):
			out[i] = parts[0]
			out[i + 1] = parts[1] + " " + out[i + 1]
	return "\n".join(out)


## Measured width of a fitted label, in metres — for callers that need to place
## a backer plate exactly behind their own text.
static func width_of(text: String, style: int, fs: int, pixel_size := 0.01) -> float:
	var longest := ""
	for l in text.split("\n"):
		if l.length() > longest.length():
			longest = l
	var s: Array = STYLE[style]
	var f: Font = _font(style, _track(style, fs))
	var w: float = f.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return (w + 2.0 * clampf(float(s[3]) * float(fs), float(s[4]), float(s[5]))) \
		* pixel_size


## Height of a fitted label, in metres (cap height for all-caps copy).
static func height_of(text: String, fs: int, pixel_size := 0.01) -> float:
	var lines := text.split("\n").size()
	var per := (LINE_BOX if _has_descender(text) else CAP + 0.06)
	return float(lines) * per * float(fs) * pixel_size


# ============================== INTERNALS ====================================
## Tracking a style may actually use at this size. Positive (wide-set) styles
## never spend more than TRACK_CAP of the em on air, and tight styles never
## close up more than half that — so a style stays itself at 300 pt and still
## fits at 20 pt.
static func _track(style: int, fs: int) -> int:
	var t := float(STYLE[style][0])
	if t > 0.0:
		return int(minf(t, TRACK_CAP * float(fs)))
	return int(maxf(t, -TRACK_CAP * 0.5 * float(fs)))


static func _font(style: int, track: int) -> Font:
	var key := "%d_%d" % [style, track]
	if _fonts.has(key):
		return _fonts[key]
	var s: Array = STYLE[style]
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = track
	fv.variation_embolden = float(s[1])
	if float(s[2]) != 0.0:
		fv.variation_transform = Transform2D(
			Vector2(1.0, 0.0), Vector2(float(s[2]), 1.0), Vector2.ZERO)
	_fonts[key] = fv
	return fv


## The same style with tracking stripped, so the solver can separate the part
## of the width that scales with size from the part that does not.
static func _plain_font(style: int) -> Font:
	if _plain.has(style):
		return _plain[style]
	var s: Array = STYLE[style]
	var f: Font
	if style == FLAT or (float(s[1]) == 0.0 and float(s[2]) == 0.0):
		f = ThemeDB.fallback_font
	else:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = float(s[1])
		if float(s[2]) != 0.0:
			fv.variation_transform = Transform2D(
				Vector2(1.0, 0.0), Vector2(float(s[2]), 1.0), Vector2.ZERO)
		f = fv
	_plain[style] = f
	return f


static func _has_descender(text: String) -> bool:
	for c in "gjpqy,;()[]{}$Q":
		if text.contains(c):
			return true
	for i in text.length():
		var ch := text[i]
		if ch >= "a" and ch <= "z":
			return true
	return false


const STYLE_NAME: Array[String] = ["FLAT", "GANTRY", "CHANNEL", "PLAQUE",
	"MARQUEE", "HOARDING", "GHOST", "STENCIL", "HANDPAINT", "BLADE", "FASCIA"]


## `godot --headless --quit-after 300 -- --signaudit` prints one row per sign
## in the whole built world: what it says, what it was given, what it drew.
## A FAIL line is a sign wider or taller than the board it is on.
static func _audit(text: String, style: int, fs: int, max_w: float,
		max_h: float, ps: float) -> void:
	if _audit_on < 0:
		_audit_on = 1 if OS.get_cmdline_user_args().has("--signaudit") else 0
		if _audit_on == 1:
			print("SIGNAUDIT | style | fs | drawn_w x drawn_h | board_w x board_h | fill% | text")
	if _audit_on == 0:
		return
	var w := width_of(text, style, fs, ps)
	var h := height_of(text, fs, ps)
	var bad := w > max_w + 0.001 or (max_h > 0.0 and h > max_h + 0.001)
	print("SIGNAUDIT %s | %-9s | %4d | %6.2f x %5.2f | %6.2f x %5.2f | %3d%% | %s" % [
		"FAIL" if bad else "ok  ", STYLE_NAME[style], fs, w, h, max_w, max_h,
		int(100.0 * w / maxf(max_w, 0.001)), text.replace("\n", " / ")])
