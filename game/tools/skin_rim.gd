extends SceneTree
## RIM LIFT, FAST — the §1 bar row, and nothing else.
##   cd game/ && godot --headless --script res://tools/skin_rim.gd 2>&1
##   ... --script res://tools/skin_rim.gd -- --piece=hem     one piece only
##
## `skin_wardrobe.gd` measures three things and takes minutes; iterating a
## meshing change against it is the slow half of the work. This runs the SAME
## clearance measurement (it calls `skin_wardrobe._clearance` rather than
## re-deriving it, so the two can never disagree) on one build bucket, prints
## the per-piece table and the one number the bar cares about:
##
##   N of M back-face vertices over 5 mm.
##
## The factory's comparable figure is 0. So is the target.
##
## It also prints BAKE MILLISECONDS per piece, because the fix for rim lift is
## resolution and resolution is paid for in bake time — a fix that reaches 0/M
## and costs twelve seconds of boot has traded one bar row for another
## (§4b: boot to playable <= 20 s).

const SKIN := preload("res://scripts/world/skinned_character.gd")
const WARD := preload("res://tools/skin_wardrobe.gd")


func _init() -> void:
	SKIN._no_disk = true
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--piece="):
			only = a.substr(8)
		elif a.begins_with("--voxdiv="):
			SKIN.VOX_DIV = float(a.substr(9))
		elif a.begins_with("--reproj="):
			SKIN.REPROJ = int(a.substr(9))
	print("VOX_DIV=%.2f REPROJ=%d" % [SKIN.VOX_DIV, SKIN.REPROJ])
	var builds: Array = [[1.07, 1.07]]
	for a in OS.get_cmdline_user_args():
		if a == "--all-buckets":
			builds = [[0.97, 0.93], [0.97, 1.07], [1.07, 1.07], [1.07, 1.22]]
	if OS.get_cmdline_user_args().has("--lib"):
		_lib()
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--cover"):
		_cover()
		quit(0)
		return
	for b: Array in builds:
		_report(float(b[0]), float(b[1]), only)
	quit(0)


func _report(cw: float, cg: float, only: String) -> void:
	var prims := SKIN._prims(cw, cg)
	var fp := SKIN._flatten(prims)
	var bg := SKIN._field_grid(prims, fp, SKIN.VOX)
	var dg := SKIN._dist_grid(bg)
	var tp: Array = []
	for pr: Dictionary in prims:
		var b := int(pr["bone"])
		if b == SKIN.B_ROOT or b == SKIN.B_TORSO or b == SKIN.B_COLLAR:
			tp.append(pr)
	var dgt := SKIN._dist_grid(SKIN._field_grid_on(tp, SKIN._flatten(tp),
		SKIN.VOX, bg))
	var pieces := SKIN._pieces(cw, cg)
	print("")
	print("RIM LIFT — build %.2f girth %.2f" % [cw, cg])
	print("%-11s %5s %6s %6s %6s %7s %7s %7s %7s %7s %11s %s"
		% ["piece", "vox", "bake", "verts", "tris", "design", "min", "mean",
			"max", "excess", "over/back", "verdict"])
	var gtot := 0
	var gover := 0
	var bake_ms := 0.0
	var pen_tot := 0
	for p in SKIN.PIECE_N:
		if only != "" and SKIN.PIECE_NAME[p] != only:
			continue
		var parts: Array = pieces[p]
		if parts.is_empty():
			continue
		if p in [SKIN.P_PLACKET, SKIN.P_COLLAR_PTS, SKIN.P_POCKET_L, SKIN.P_POCKET_R]:
			# These ship as tailored fabric meshes (_tailored_piece), not shells;
			# baking their old shell parts here would grade geometry nobody sees.
			print("%-11s   ---  TAILORED (explicit fabric mesh; not a shell, not graded here)"
				% SKIN.PIECE_NAME[p])
			continue
		var t0 := Time.get_ticks_usec()
		var arr := SKIN._bake_piece(parts, bg, dg, cw, dgt)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		bake_ms += ms
		if arr.is_empty():
			print("%-11s   ---  EMPTY BAKE" % SKIN.PIECE_NAME[p])
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var offs := PackedFloat32Array()
		var shallow := 9.0
		for pt: Dictionary in parts:
			var o := float(pt["off"]) if int(pt["t"]) == 0 else float(pt["clr"])
			offs.append(o)
			shallow = minf(shallow, o)
		const H := 0.002
		var lo := 9.0
		var hi := -9.0
		var acc := 0.0
		var cnt := 0
		var wex := 0.0
		var phi := Vector3.ZERO
		var pen := 0
		var nover := 0
		for i in v.size():
			var q := v[i]
			var gr := Vector3(
				SKIN._field(fp, q + Vector3(H, 0, 0))
					- SKIN._field(fp, q - Vector3(H, 0, 0)),
				SKIN._field(fp, q + Vector3(0, H, 0))
					- SKIN._field(fp, q - Vector3(0, H, 0)),
				SKIN._field(fp, q + Vector3(0, 0, H))
					- SKIN._field(fp, q - Vector3(0, 0, H)))
			if gr.length() < 1e-9 or n[i].dot(gr) > -0.80 * gr.length():
				continue
			var c := WARD._clearance(fp, q, gr)
			if c < -0.5:
				continue
			if c < 0.0:
				pen += 1
				continue
			var mine := -1
			var best := 1e9
			for pi in parts.size():
				var d: float = SKIN._part_sdf(parts[pi], q, c)
				if d < best:
					best = d; mine = pi
			var stacked := false
			var dirn := gr.normalized()
			for st in 8:
				var tt := c * (float(st) + 0.5) / 8.0
				var sp := q - dirn * tt
				for pi in parts.size():
					if pi == mine:
						continue
					if SKIN._part_sdf(parts[pi], sp, c - tt) < 0.0:
						stacked = true
						break
				if stacked:
					break
			if stacked:
				continue
			var ex: float = absf(c - offs[mine])
			if ex * 1000.0 > 5.0:
				nover += 1
			if c < lo: lo = c
			if c > hi: hi = c
			if ex > wex:
				wex = ex; phi = q
			acc += c; cnt += 1
		pen_tot += pen
		if cnt == 0:
			print("%-11s %5.1f %6.0f %6d %6d   no unstacked back-face vertex"
				% [SKIN.PIECE_NAME[p], SKIN._piece_vox(parts) * 1000.0, ms,
					v.size(), idx.size() / 3])
			continue
		var vol := WARD.pt_kind(parts) == 1
		var bad := wex * 1000.0 > 5.0 and not vol
		gtot += cnt
		gover += (nover if not vol else 0)
		print("%-11s %5.1f %6.0f %6d %6d %6.1f %7.1f %7.1f %7.1f %7.1f %5d/%-5d %s"
			% [SKIN.PIECE_NAME[p], SKIN._piece_vox(parts) * 1000.0, ms,
				v.size(), idx.size() / 3, shallow * 1000.0, lo * 1000.0,
				acc / float(cnt) * 1000.0, hi * 1000.0, wex * 1000.0,
				nover, cnt,
				("OVER 5 mm at (%.3f,%.3f,%.3f)" % [phi.x, phi.y, phi.z]) if bad
				else (("volume" if vol else "ok")
					+ ("  %d PENETRATING" % pen if pen > 0 else ""))])
	print("  FLAT-TRIM VERTEX TALLY: %d of %d over 5 mm (%.3f%%)  "
		% [gover, gtot, 100.0 * float(gover) / float(maxi(gtot, 1))]
		+ "penetrating: %d   garment bake: %.0f ms" % [pen_tot, bake_ms])


## THE SHIPPING NUMBER. `_report` counts triangles PER PIECE, before the merge
## and before `_garment_mesh` generates the LOD chain. What a frame actually
## draws is one merged surface per character, so this prints that — per
## archetype, which is the unit the crowd is built out of.
func _cover() -> void:
	const FACT := preload("res://scripts/world/character_factory.gd")
	var names := ["CASUAL", "WESTERN", "WORKER", "OFFICE", "SERVICE", "STREET",
		"SCRUBS", "GAMEDAY"]
	print("")
	print("ARCHETYPE GARMENT COST — merged, after generate_lods")
	print("%-9s %8s %8s  %s" % ["outfit", "gtris", "gverts", "pieces"])
	var rows: Array = []
	for o in 8:
		var r := RandomNumberGenerator.new()
		r.seed = hash("wardrobe|%d" % o)
		var cfg := FACT._person(r, FACT.SKIN_TONES[o % 6], FACT.HAIRS[o % 5],
			1.0, 1.02)
		cfg["shirt"] = FACT.SHIRTS[o % FACT.SHIRTS.size()]
		cfg["pants"] = FACT.PANTS[o % FACT.PANTS.size()]
		cfg["hat_color"] = FACT.HAT_COLORS[0]
		FACT._dress(cfg, r, o)
		rows.append([names[o], cfg])
	var rc := RandomNumberGenerator.new()
	rc.seed = 7
	rows.append(["COP", FACT.cop_config(rc)])
	rows.append(["BOOK", FACT.book_config()])
	var tot := 0
	for e in rows:
		var cfg: Dictionary = e[1]
		var lay: int = SKIN._layout(cfg)
		var pn: Array = []
		for p in SKIN.PIECE_N:
			if lay & (1 << p):
				pn.append(SKIN.PIECE_NAME[p])
		var gm: ArrayMesh = SKIN._garment_mesh(lay,
			float(cfg.get("build", 1.0)), float(cfg.get("girth", 1.0)))
		var gt := 0
		var gv := 0
		if gm != null:
			var a := gm.surface_get_arrays(0)
			gt = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			gv = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		tot += gt
		print("%-9s %8d %8d  %s" % [e[0], gt, gv, ", ".join(pn)])
	print("  mean garment %d tris over %d archetypes" % [tot / rows.size(),
		rows.size()])


## THREADED vs NOT, both arms in ONE process, back to back. Wall clock across
## separate processes is worthless here: this machine has been running five to
## eight concurrent Godot instances all cycle, so two runs minutes apart are not
## comparable. Two arms seconds apart are.
func _lib() -> void:
	print("")
	print("PIECE-LIB BAKE — one build bucket, both arms in this process")
	for th in [false, true]:
		SKIN.THREADED = th
		SKIN._lib_cache.clear()
		var t0 := Time.get_ticks_usec()
		var lib := SKIN._piece_lib(1.07, 1.07, "bench_%d" % int(th))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var tris := 0
		for k in lib:
			tris += ((lib[k] as Array)[Mesh.ARRAY_INDEX]
				as PackedInt32Array).size() / 3
		print("  THREADED=%-5s  %8.0f ms   %d pieces  %d tris"
			% [str(th), ms, lib.size(), tris])
	SKIN.THREADED = true
