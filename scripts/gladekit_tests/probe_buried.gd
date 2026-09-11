extends SceneTree
## Scratch probe: what does `buried_style` actually do in scenes/dev/whinbek.tscn?
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_buried.gd

const SCENE := "res://scenes/dev/gladekit/whinbek.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	for i in 12:
		await process_frame
	await physics_frame

	var walls: Array[GladeWall] = []
	_collect(scene, walls)

	print("\n=== who overlaps whom ===")
	for w in walls:
		var vols := w.junction_volumes()
		var b := GladeJunction.bounds(vols)
		print("%-10s rank %d  vols %d  aabb %s .. %s  bricks %d"
				% [w.name, w.junction_rank, vols.size(), _v(b.position), _v(b.end),
						w.snap_transforms.size()])

	print("\n=== pairwise seams ===")
	for i in walls.size():
		for j in range(i + 1, walls.size()):
			var a := walls[i]
			var b := walls[j]
			var seams: Array = []
			for mine: GladeVolume in a.junction_volumes():
				seams.append_array(GladeSeam.between(mine, b.junction_volumes()))
			seams = GladeSeam.significant(seams)
			if seams.is_empty():
				continue
			var count := {}
			var biggest := {}
			for s: GladeSeam in seams:
				var k := "%s/%s" % [GladeSeam.Kind.keys()[s.kind], GladeSeam.Turn.keys()[s.turn]]
				count[k] = int(count.get(k, 0)) + 1
				biggest[k] = maxf(float(biggest.get(k, 0.0)), s.measure())
			var parts: Array[String] = []
			for k in count:
				parts.append("%d %s (biggest %.2f)" % [count[k], k, biggest[k]])
			print("%s x %s : %s" % [a.name, b.name, ", ".join(parts)])

	print("\n=== how fat is a claim compared with the building it stands for ===")
	for w in walls:
		var st := GladeUtil.current_style(w.style)
		print("%-10s depth/2 %.2f + top_jetty %.2f = claim reaches %.2f m from the curve"
				% [w.name, st.depth * 0.5, w.top_jetty(), st.depth * 0.5 + w.top_jetty()])

	print("\n=== how much stone each wall loses, and what a buried style gives back ===")
	for w in walls:
		await _one(w, walls)

	quit(0)


## WHERE A WALL'S MASS ACTUALLY IS — which is now just its claim.
##
## This used to be a correction. `junction_volumes()` returned ONE prism fattened by `top_jetty()`
## over the whole height, so at ground level it reached out past the building by that much, and this
## function shrank the polygon back by the jetty to recover the real envelope. Since the claim went
## per-storey the correction is not merely unnecessary, it is WRONG TWICE: `vols[0]` is the ground
## storey rather than the widest one, and shrinking it again by the top jetty pulls it inside the
## stone. A probe that measures a stale compensation measures its own arithmetic.
##
## So the yardstick is the claim itself. That the two are now the same thing is exactly the property
## this probe exists to report on.
func _envelopes(w: GladeWall) -> Array:
	return w.junction_volumes()


## Three measurements for one wall: standing alone, standing in the scene, and standing in the
## scene with a buried style that is a COPY OF ITS OWN. The third should reproduce the first
## exactly — the two fill passes are supposed to cover the surface once between them.
func _one(w: GladeWall, all: Array[GladeWall]) -> void:
	var here := _sig(w)
	var was := w.position
	w.position = was + Vector3(500, 0, 500)
	w.rebuild()
	await process_frame
	var alone := _sig(w)
	w.position = was
	w.rebuild()
	await process_frame

	if alone.size() == here.size():
		print("%-10s no stone lost (%d bricks) -- nothing buries it" % [w.name, alone.size()])
		return

	_dress(w, false)
	w.rebuild()
	await process_frame
	var same := _sig(w)

	_dress(w, true)
	w.rebuild()
	await process_frame
	var red := _sig(w)

	var kept := 0
	for k in same:
		if alone.has(k):
			kept += 1
	print("%-10s alone %d | in scene %d (lost %d) | buried=self %d, of which %d are also in the solo wall | buried=red %d"
			% [w.name, alone.size(), here.size(), alone.size() - here.size(), same.size(), kept,
					red.size()])
	var missing := 0
	for k in alone:
		if not same.has(k):
			missing += 1
	var extra := 0
	for k in same:
		if not alone.has(k):
			extra += 1
	print("%-10s   vs solo: %d bricks missing, %d bricks that solo does not have"
			% [w.name, missing, extra])

	# AND WHERE DID THE REFILL LAND? A buried stone belongs inside the building that swallowed it.
	# Any that is inside nobody's envelope is standing in the open air.
	var envs: Array = []
	for other in all:
		if other != w:
			envs.append_array(_envelopes(other))
	var outside := 0
	var lowest := 1.0e9
	for k in same:
		if here.has(k):
			continue
		# the snapshot is in the wall's own space -- that is what makes the solo comparison above
		# work at all, since the solo run is taken 500 m away
		var p: Vector3 = w.to_global(same[k])
		var inside := false
		for e in envs:
			if e.contains(p):
				inside = true
				break
		if not inside:
			outside += 1
			lowest = minf(lowest, p.y)
	print("%-10s   of the refilled stone, %d pieces are inside NOBODY (lowest at y %.2f)"
			% [w.name, outside, lowest if outside > 0 else 0.0])
	_undress(w)
	w.rebuild()
	await process_frame


## Give every style this wall uses a buried style. `tinted` makes it unmistakable on camera;
## otherwise it is a plain copy, which is the interesting case: the buried pass should then be
## indistinguishable from the stone the junction took away.
func _dress(w: GladeWall, tinted: bool) -> void:
	_undress(w)
	w.style = _with_buried(w.style, tinted)
	for s in w.storeys:
		if s and s.style:
			s.style = _with_buried(s.style, tinted)


func _undress(w: GladeWall) -> void:
	if w.has_meta("orig_style"):
		w.style = w.get_meta("orig_style")
		for i in w.storeys.size():
			var s: GladeStorey = w.storeys[i]
			if s and s.has_meta("orig_style"):
				s.style = s.get_meta("orig_style")


func _with_buried(st: GladeStyle, tinted: bool) -> GladeStyle:
	if st == null:
		return null
	var outer: GladeStyle = st.duplicate()
	var inner: GladeStyle = st.duplicate()
	if tinted:
		inner.palette = [Color(0.9, 0.2, 0.2)] as Array[Color]
		inner.palette_weights = PackedFloat32Array([1])
		inner.panel_color = Color(0.9, 0.2, 0.2)
		inner.timber_color = Color(0.6, 0.1, 0.1)
	outer.buried_style = inner
	return outer


func _sig(w: GladeWall) -> Dictionary:
	var d := {}
	for t in w.snap_transforms:
		d["%.2f,%.2f,%.2f" % [t.origin.x, t.origin.y, t.origin.z]] = t.origin
	return d


func _collect(n: Node, out: Array[GladeWall]) -> void:
	if n is GladeWall:
		var w: GladeWall = n
		w.set_meta("orig_style", w.style)
		for s in w.storeys:
			if s:
				s.set_meta("orig_style", s.style)
		out.append(w)
	for c in n.get_children():
		_collect(c, out)


func _turn(s: GladeSeam) -> String:
	return "concave" if s.concave else "convex"


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
