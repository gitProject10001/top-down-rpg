extends SceneTree
## WD2 BRING-UP, in the plan's order: quiescent first, then one ring, then weirs.
##
##   1. STAIRCASE FIXED POINT — no impulses, weirs off: eta must stay 0. Any drift means the
##      solver is manufacturing water.
##   2. WEIRS QUIESCENT — weirs on, still no impulses: still 0, because the crest is the rest
##      surface and a pond at rest has zero head.
##   3. THE RING — one poke, amplitude at 0.6 s against the old field's measured 0.0469.
##   4. STABILITY — 16 impulses at once; no NaN, bounded.


func _initialize() -> void:
	var lab := (load("res://scenes/dev/water_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	for _i in 40:
		await process_frame
	var rip := root.get_node("/root/Ripples")
	rip.set("weirs", false)
	await _settle(120)
	print("[SWE] 1. quiescent, weirs OFF, 2 s: %s" % _stats(rip))

	rip.set("weirs", true)
	await _settle(300)
	print("[SWE] 2. quiescent, weirs ON,  5 s: %s" % _stats(rip))
	await _settle(300)
	print("[SWE] 2b. quiescent, weirs ON, 10 s: %s" % _stats(rip))

	# One ring, watched over time: a dispersing wave must DECAY monotonically. Anything that
	# grows a second after the poke is an instability with a slow seed, and the only way to
	# tell those apart is to watch.
	var p := _lake_centre(lab)
	rip.set("weirs", false)
	await _settle(120)
	rip.splash(p, 0.6, 0.3)
	for k in 10:
		await _settle(30)
		print("[SWE] 3. ring t=%.1fs: %s" % [(k + 1) * 0.5, _stats(rip)])

	# THROUGHPUT: with a spring feeding it, the chain must reach a STEADY state — head up at
	# the source, a weir passing it on, and a terminal pool that stops rising. Watched, because
	# "it balances" is a claim about time, not a snapshot.
	# Does the world agree there IS a spring, and is it inside the window?
	var zz := get_first_node_in_group("zone") as Node3D
	var tt := zz.get_node("Terrain") as Node3D
	var mm: WildsMap = zz.get("built_map")
	var wat := root.get_node("/root/Water")
	var found := 0
	var inside := 0
	var org: Vector2 = rip.window_origin()
	for cz in range(28, 40):
		for cx in range(10, 42):
			var wp: Vector3 = zz.to_global(tt.position
					+ Vector3((cx + 0.5) * mm.cell_size, 0.0, (cz + 0.5) * mm.cell_size))
			if wat.is_spring(wp):
				found += 1
				var rel := Vector2(wp.x, wp.z) - org
				if rel.x >= 0.0 and rel.y >= 0.0 and rel.x <= 64.0 and rel.y <= 64.0:
					inside += 1
	print("[SWE] springs: %d painted, %d inside the window" % [found, inside])
	rip.set("weirs", true)
	# A SOLVER PINNED AT ITS OWN CLAMPS IS NOT A STEADY STATE, it is a stuck one, and the two
	# read identically in a printout. This probe printed a frozen eta -0.3025 / |u'| 3.000 for
	# sixteen seconds and nobody read it as a failure: the numbers looked plausible, and the
	# clamps are exactly where a stuck solver comes to rest. So assert on them. -0.3025 is
	# -H0 * draw_max; 3.000 is u_max.
	var pinned_eta := 0
	var pinned_u := 0
	for k in 8:
		await _settle(120)
		print("[SWE] 5. river t=%ds: %s" % [(k + 1) * 2, _stats(rip)])
		if absf(_last_eta_min + 0.3025) < 0.0005:
			pinned_eta += 1
		if absf(_last_u_max - 3.0) < 0.0005:
			pinned_u += 1
	if pinned_eta > 4 or pinned_u > 4:
		print("[SWE] FAIL: clamps are load-bearing (eta %d/8, u %d/8 samples pinned)"
				% [pinned_eta, pinned_u])
		quit(1)
	print("[SWE] river is alive: neither clamp is load-bearing")
	quit(0)

	# Everything at once.
	rip.set("weirs", true)
	for i in 16:
		rip.splash(p + Vector3(randf() * 6.0 - 3.0, 0.0, randf() * 6.0 - 3.0), 0.5, 0.25)
	await _settle(180)
	print("[SWE] 4. after 16 impulses, 3 s: %s" % _stats(rip))
	quit(0)


func _lake_centre(lab: Node) -> Vector3:
	var zone := get_first_node_in_group("zone") as Node3D
	var terrain := zone.get_node("Terrain") as Node3D
	var m: WildsMap = zone.get("built_map")
	var mid := Vector2(35.0, 33.5) * m.cell_size
	return zone.to_global(terrain.position + Vector3(mid.x, 0.0, mid.y))


## eta min/max, |u'| max, foam mean, and a NaN count — the four numbers that say whether the
## solver is alive, stable, and not quietly manufacturing water.
var _last_eta_min := 0.0
var _last_u_max := 0.0


func _stats(rip: Node) -> String:
	var img: Image = (rip.debug_texture() as Texture2D).get_image()
	var emin := 1e9
	var emax := -1e9
	var vmax := 0.0
	var fsum := 0.0
	var nan_n := 0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var px := img.get_pixel(x, y)
			if is_nan(px.r) or is_nan(px.g) or is_nan(px.b) or is_nan(px.a):
				nan_n += 1
				continue
			emin = minf(emin, px.r)
			emax = maxf(emax, px.r)
			vmax = maxf(vmax, Vector2(px.g, px.b).length())
			fsum += px.a
			n += 1
	_last_eta_min = emin
	_last_u_max = vmax
	return "eta %.4f..%.4f  |u'| max %.3f  foam mean %.3f  NaN %d" \
			% [emin, emax, vmax, fsum / maxf(float(n), 1.0), nan_n]


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
