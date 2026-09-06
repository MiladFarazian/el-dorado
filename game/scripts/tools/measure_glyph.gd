extends Node
## TEMPORARY audit tool (M22) — for every real sign in the game, compute what
## the shipped `0.66` heuristic DREW versus the board it was drawn on, and what
## the exact solver draws instead. Delete after the pass.
##   godot --headless --quit-after 120 res://scenes/measure_glyph.tscn

const SIGN := preload("res://scripts/world/sign_kit.gd")
const OUT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/signaudit.txt"

# [site, text, board_w, board_h (0=free), old cap, old outline, pixel_size]
# Board sizes are the ACTUAL panel geometry read out of each builder, not the
# max_w the call site was passing (several were passing more than they had).
const SITES: Array = [
	["city/billboard name", "PARLAYPAL SPORTSBOOK LOUNGE", 12.0, 3.0, 190, 18, 0.01],
	["city/billboard name", "SMOKE 'EM IF YOU GOT 'EM", 12.0, 3.0, 190, 18, 0.01],
	["city/billboard name", "THE TEXAS SLEDGEHAMMER", 12.0, 3.0, 190, 18, 0.01],
	["city/billboard name", "HOLLERBURGER", 12.0, 3.0, 190, 18, 0.01],
	["city/billboard name", "OMNIMIND", 12.0, 3.0, 190, 18, 0.01],
	["city/billboard sub", "HOMES FROM THE $400s. TREES FROM 2041.", 12.0, 1.6, 95, 18, 0.01],
	["city/billboard sub", "1-800-WRECKED  ·  SE HABLA JUSTICE", 12.0, 1.6, 95, 18, 0.01],
	["city/storefront", "LONGHORN WRECKER & RECOVERY", 18.0, 1.7, 105, 18, 0.01],
	["city/storefront", "FENCE POST RANCH WATER", 18.0, 1.7, 105, 18, 0.01],
	["city/storefront", "KWIKSIP", 18.0, 1.7, 105, 18, 0.01],
	["city/ROOFTOP", "LONGHORN DYNAMICS", 26.0, 0.0, 300, 26, 0.01],
	["city/ROOFTOP", "BOLO CAPITAL", 26.0, 0.0, 300, 26, 0.01],
	["city/ROOFTOP", "TEXOTRONICS", 26.0, 0.0, 300, 26, 0.01],
	["city/ROOFTOP", "BLUR+", 26.0, 0.0, 300, 26, 0.01],
	["city/blade", "N 1ST AVE", 2.6, 0.46, 44, 12, 0.01],
	["city/MART flag", "MART", 0.98, 0.64, 28, 12, 0.01],
	["city/MART tagline", "NOW SERVING 40% FEWER CITIES", 3.2, 0.5, 20, 12, 0.01],
	["city/shelter ad", "HOLLERBURGER", 1.4, 0.5, 30, 12, 0.01],
	["greybox/TRUST CROWN", "CATTLEMAN'S TRUST", 26.0, 0.0, 340, 24, 0.01],
	["greybox/hosp fascia", "EMERGENCY", 11.0, 1.2, 150, 16, 0.01],
	["greybox/hosp ward", "COUNTY GENERAL", 42.0, 0.0, 210, 16, 0.01],
	["greybox/hosp ROADSIDE", "COUNTY GENERAL", 7.5, 1.1, 120, 16, 0.01],
	["greybox/hosp ROADSIDE", "HOSPITAL  ·  EMERGENCY", 7.5, 0.9, 70, 16, 0.01],
	["greybox/hosp ROADSIDE", "YOU BLEED. WE BILL.", 7.5, 0.8, 52, 16, 0.01],
	["fwy/GANTRY single", "DOWNTOWN DORADO", 7.6, 1.0, 110, 10, 0.01],
	["fwy/GANTRY pair", "DOWNTOWN DORADO", 5.4, 1.0, 110, 10, 0.01],
	["fwy/GANTRY pair", "THREEFORK FLOODWAY", 5.4, 1.0, 110, 10, 0.01],
	["fwy/GANTRY sub", "EXIT 1/2 MILE", 5.4, 0.8, 78, 10, 0.01],
	["fwy/trailblazer", "DOWNTOWN DORADO", 4.2, 0.8, 62, 10, 0.01],
	["fwy/trailblazer", "MIDDLINGTON", 4.2, 0.8, 62, 10, 0.01],
	["fwy/gore", "EXIT", 1.9, 1.35, 95, 10, 0.01],
	["fwy/column poster", "SLEDGEHAMMER", 0.74, 0.5, 12, 10, 0.01],
	["fwy/column poster", "NETWORK", 0.74, 0.5, 12, 10, 0.01],
	["fwy/drive-thru", "CLUCK ALMIGHTY", 0.88, 0.4, 26, 10, 0.01],
	["lm/church fascia", "OVERFLOW FELLOWSHIP", 40.0, 2.6, 200, 10, 0.01],
	["lm/marquee L1", "OVERFLOW FELLOWSHIP", 8.4, 1.0, 60, 10, 0.01],
	["lm/marquee L2", "SEEDFAITH APP: GIVE 24/7", 8.4, 0.8, 42, 10, 0.01],
	["lm/marquee L3", "12 CAMPUSES · ONE OVERFLOW", 8.4, 0.7, 34, 10, 0.01],
	["lm/stadium name", "RUSTLERS STADIUM", 26.0, 3.0, 190, 10, 0.01],
	["lm/stadium sub", "HOME OF AMERICA'S FRANCHISE™", 26.0, 1.2, 52, 10, 0.01],
	["lm/gigastead barn", "GIGASTEAD", 120.0, 10.5, 300, 10, 0.01],
	["lm/gigastead sign", "GIGASTEAD", 14.0, 2.6, 200, 10, 0.01],
	["lm/gigastead sub", "YOUR NEIGHBORS ALREADY SAID YES", 14.0, 1.0, 56, 10, 0.01],
	["lm/no trespassing", "NO TRESPASSING\nRANGE WARDENS PATROL", 1.5, 1.05, 9, 10, 0.01],
	["lm/water tower", "MIDDLINGTON", 12.0, 0.0, 150, 10, 0.01],
	["lm/pump shed", "CITY OF MIDDLINGTON UTILITIES", 3.2, 0.8, 14, 10, 0.01],
	["dt/lobby plaque", "OVERFLOW FELLOWSHIP", 14.0, 0.4, 74, 14, 0.01],
	["dt/lobby plaque", "PIONEER VISION", 14.0, 0.4, 74, 14, 0.01],
	["dt/roof ad", "MAY BELLE COSMETICS", 12.9, 2.0, 190, 14, 0.01],
	["dt/roof sub", "SOMEBODY IS SETTLING FOR YOU", 12.9, 1.2, 82, 14, 0.01],
	["dt/GHOST wall", "WILD WANDA'S", 20.0, 0.0, 230, 14, 0.01],
	["dt/hoarding head", "PIONEER VISION DEVELOPMENT", 20.0, 0.9, 96, 14, 0.01],
	["dt/hoarding sub", "A BOLO CAPITAL NEIGHBORHOOD", 20.0, 0.7, 52, 14, 0.01],
	["dt/deck", "$12 EARLY BIRD · $40 EVENT", 16.0, 0.9, 60, 14, 0.01],
	["dt/texchange", "THE TEXCHANGE", 18.0, 1.9, 120, 14, 0.01],
	["plaza/pay hut", "PARKING $12 · EVENT PRICING WHENEVER", 2.0, 0.5, 34, 10, 0.01],
	["wild/depth board", "6\n4\n2", 0.9, 3.4, 88, 0, 0.01],
	["wild/bridge fascia", "THREEFORK FLOODWAY  ·  NO SWIMMING  ·  NO KIDDING", 24.0, 1.0, 80, 6, 0.01],
	["wild/column tag", "CCC", 1.69, 1.0, 90, 8, 0.01],
	["wild/floodway", "CITY OF DORADO · NO SWIMMING", 46.0, 0.0, 260, 14, 0.01],
	["facade/blade", "LONGHORN WRECKER & RECOVERY", 2.6, 0.95, 46, 12, 0.01],
	["facade/blade", "KWIKSIP", 2.6, 0.95, 46, 12, 0.01],
	["slab/road", "CANDYLAND\nSTRIP", 11.0, 0.0, 999, 16, 0.01],
	["M12/dispatch", "LONGHORN DISPATCH", 4.6, 1.0, 60, 0, 0.0075],
	["M18/night board", "LONGHORN WRECKER — NIGHT BOARD\nWE OWN THAT TOO", 5.0, 1.3, 54, 0, 0.0075],
	["M18/pedestal", "OVERFLOW FLEET\nCHARGE + IMMOBILISER\nUNIT 3 · HOLD 4471", 0.52, 0.5, 30, 0, 0.0038],
	["M18/kiosk", "SEEDFAITH\nGIVE 24/7 · TAP TO SOW", 0.64, 0.6, 30, 0, 0.0040],
	["M18/target flank", "OVERFLOW FELLOWSHIP\nOUTREACH FLEET · UNIT 3", 4.86, 0.8, 34, 0, 0.0042],
]

var _lines: PackedStringArray = []


func _p(s: String) -> void:
	_lines.append(s)
	print(s)


## Sites whose shipped code has NO fit law at all — a hard-coded font_size that
## was never checked against the board. These are the interesting ones.
const FIXED: Dictionary = {
	"city/ROOFTOP": 300, "greybox/TRUST CROWN": 340,
	"greybox/hosp fascia": 150, "greybox/hosp ward": 210,
	"greybox/hosp ROADSIDE": -1,            # 120 / 70 / 52, taken from `cap`
	"plaza/pay hut": 34, "wild/depth board": 88, "wild/bridge fascia": 80,
	"M12/dispatch": 60, "M18/night board": 54, "M18/pedestal": 30,
	"M18/kiosk": 30, "M18/target flank": 34,
}


## Exactly what the shipped code did.
func _old(site: String, text: String, board: float, cap: int, ps: float) -> Array:
	var font: Font = ThemeDB.fallback_font
	var longest := ""
	for l in text.split("\n"):
		if l.length() > longest.length():
			longest = l
	var fs := cap
	var law := "0.66"
	if FIXED.has(site):
		law = "FIXED"
		fs = (cap if int(FIXED[site]) < 0 else int(FIXED[site]))
	elif cap >= 999:
		law = "0.66"
		fs = int(board / (9.0 * 0.66 * ps))          # slab_cruise's variant
	else:
		fs = mini(cap, int(board / (float(maxi(longest.length(), 1)) * 0.66 * ps)))
	fs = maxi(fs, 4)
	var w: float = font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs).x * ps
	return [fs, w, law]


func _ready() -> void:
	var font: Font = ThemeDB.fallback_font
	_p("FONT: %s    mean uppercase advance = %.4f  (the code assumed 0.66)" % [
		font.get_font_name(),
		_alpha_mean(font)])
	_p("")
	_p("%-22s %-36s %5s %5s %5s %6s  %5s %6s %5s  %s" % [
		"SITE", "TEXT", "law", "bdW", "oFS", "oldW", "nFS", "newW", "fill", "VERDICT"])
	var fails := 0
	var starved := 0
	for row_v: Variant in SITES:
		var r: Array = row_v
		var site: String = r[0]
		var text: String = r[1]
		var bw: float = r[2]
		var bh: float = r[3]
		var cap: int = r[4]
		var ps: float = r[6]
		var old: Array = _old(site, text, bw, cap, ps)
		var old_fs: int = old[0]
		var old_w: float = old[1]
		# The new solver, in a neutral style so this compares fit-to-fit.
		var new_fs := SIGN.fit_size(text, SIGN.FLAT, bw, bh, (cap if cap < 999 else 400), ps)
		var new_w := SIGN.width_of(text, SIGN.FLAT, new_fs, ps)
		var verdict := "ok"
		if old_w > bw + 0.001:
			verdict = "OVERFLOW %+.2f m -> drew %d%% of the board" % [
				old_w - bw, int(100.0 * old_w / bw)]
			fails += 1
		elif old_w < bw * 0.55:
			verdict = "starved: filled only %d%%" % int(100.0 * old_w / bw)
			starved += 1
		_p("%-22s %-36s %5s %5.1f %5d %6.2f  %5d %6.2f %4d%%  %s" % [
			site, text.replace("\n", "/"), old[2], bw, old_fs, old_w,
			new_fs, new_w, int(100.0 * new_w / bw), verdict])
	_p("")
	_p("SHIPPED STATE: %d of %d audited signs OVERFLOW their board; %d more fill under 55%% of it."
		% [fails, SITES.size(), starved])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


func _alpha_mean(font: Font) -> float:
	var up := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var tot := 0.0
	for i in up.length():
		tot += font.get_string_size(up[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x / 100.0
	return tot / 26.0
