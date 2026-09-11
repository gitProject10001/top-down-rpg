extends SceneTree
## GladeKit invariant suite — headless, exit-code, `--script` mode. Same shape as the dungeon's
## verify_dungeon.gd, including its hard lesson: every suite reports completion, and a crashed
## awaited suite fails the run instead of silently unwinding into a false PASS.
##
## Run:
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/verify_gladekit.gd

const EXPECTED_SUITES := 58
var _fails: Array[String] = []
var _suites := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _determinism_suite()
	await _stability_suite()
	await _post_suite()
	await _opening_suite()
	await _collision_suite()
	await _ground_suite()
	await _path_suite()
	await _crossing_suite()
	await _drop_suite()
	await _roof_suite()
	await _battlement_suite()
	await _weather_suite()
	await _scatter_suite()
	await _storey_suite()
	await _timber_suite()
	await _prop_suite()
	await _dormer_suite()
	await _box_suite()
	await _corner_suite()
	await _jamb_suite()
	await _dormer_cut_suite()
	await _cylinder_suite()
	await _roof_shape_suite()
	await _junction_suite()
	await _floor_suite()
	await _faces_suite()
	await _seam_suite()
	await _buried_suite()
	await _valley_suite()
	await _tee_suite()
	await _snap_suite()
	await _shapes_suite()
	await _flare_suite()
	await _adobe_suite()
	await _clay_suite()
	await _profile_suite()
	await _roof_mesh_suite()
	await _claim_storey_suite()
	await _lean_suite()
	await _anchor_suite()
	await _ledge_suite()
	await _bay_grid_suite()
	await _bridge_suite()
	await _paint_suite()
	await _mass_arris_suite()
	await _panel_suite()
	await _mass_merge_suite()
	await _mass_storey_suite()
	await _mass_door_suite()
	await _mass_roof_suite()
	await _mass_quoin_suite()
	await _mass_bevel_suite()
	await _reveal_suite()
	await _module_suite()
	await _module_role_suite()
	await _module_named_suite()
	await _module_fit_suite()
	await _mass_module_suite()
	_finish()


# --- helpers -------------------------------------------------------------------------------

func _wall(points: Array, height := 2.4, seed_v := 7) -> GladeWall:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	w.curve = c
	w.rng_seed = seed_v
	w.wall_height = height
	root.add_child(w)                          # _ready rebuilds synchronously
	return w


## Every brick of a wall as one sorted, rounded signature list. Reads the wall's CPU-side
## snapshot: the headless dummy renderer does not retain MultiMesh buffers, so reading them back
## from the MultiMesh here would return identity transforms — and a determinism test comparing
## zeros to zeros passes vacuously.
func _bricks(w: GladeWall) -> Array[String]:
	var out: Array[String] = []
	for i in w.snap_transforms.size():
		var t := w.snap_transforms[i]
		var col := w.snap_colors[i]
		out.append("%.2f,%.2f,%.2f|%.2f|%s" % [t.origin.x, t.origin.y, t.origin.z,
				t.basis.get_scale().x, col.to_html(false)])
	out.sort()
	return out


func _boxes(w: GladeWall) -> Array:
	var out: Array = []
	for c in w.get_children(true):
		if c is StaticBody3D:
			for s in c.get_children():
				if s is CollisionShape3D and (s as CollisionShape3D).shape is BoxShape3D:
					out.append(s)
	return out


func _point_in_boxes(boxes: Array, p: Vector3) -> bool:
	for s: CollisionShape3D in boxes:
		var local: Vector3 = s.global_transform.affine_inverse() * p
		var half: Vector3 = ((s.shape as BoxShape3D).size) * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false



## A surface's vertices EXPANDED THROUGH ITS INDEX BUFFER — three per triangle, in order.
##
## Every mesh the kit commits is indexed now (`GladePresent.commit`), which is worth about a third of
## the vertex data and is invisible in the picture. It is NOT invisible to a test that walked the
## vertex array in threes: an indexed surface stores each corner once, so stepping by three reads a
## different triangle each time and the answer is nonsense rather than merely wrong. Nine assertions
## went red the moment indexing landed, all of them here rather than in the addon.
##
## This restores the shape those tests were written against, and it is the same both-ways read
## `scripts/dev/atlas/atlas_wire.gd` already does for the wireframe.
static func _tri_verts(mesh: Mesh, surface := 0) -> PackedVector3Array:
	if mesh == null or mesh.get_surface_count() <= surface:
		return PackedVector3Array()
	var arr := mesh.surface_get_arrays(surface)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null 			else PackedInt32Array()
	if idx.is_empty():
		return v
	var out := PackedVector3Array()
	for i in idx:
		out.append(v[i])
	return out

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _done(name: String) -> void:
	print("[VERIFY] %s suite done" % name)
	_suites += 1


func _finish() -> void:
	_check(_suites == EXPECTED_SUITES,
			"only %d/%d suites ran to completion — one crashed" % [_suites, EXPECTED_SUITES])
	var verdict := "PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()
	print("[VERIFY] GLADEKIT %s" % verdict)
	for f in _fails:
		print("  FAIL: %s" % f)
	quit(0 if _fails.is_empty() else 1)


# --- suites --------------------------------------------------------------------------------

## Same curve + same seed = the same wall, brick for brick.
func _determinism_suite() -> void:
	await process_frame
	var a := _wall([Vector3.ZERO, Vector3(9, 0, 0), Vector3(9, 0, 6)])
	var b := _wall([Vector3.ZERO, Vector3(9, 0, 0), Vector3(9, 0, 6)])
	await process_frame
	var sig_a := _bricks(a)
	var sig_b := _bricks(b)
	_check(not sig_a.is_empty(), "determinism: wall generated no bricks")
	_check(sig_a == sig_b, "determinism: identical walls differ")
	# different seed must actually differ
	var c := _wall([Vector3.ZERO, Vector3(9, 0, 0), Vector3(9, 0, 6)], 2.4, 8)
	await process_frame
	_check(_bricks(c) != sig_a, "determinism: seed change changed nothing")
	a.free(); b.free(); c.free()
	_done("determinism")


## EDIT LOCALITY — the tool's soul. Extending the far end must leave near-end bricks untouched.
func _stability_suite() -> void:
	var a := _wall([Vector3.ZERO, Vector3(8, 0, 0)])
	var b := _wall([Vector3.ZERO, Vector3(14, 0, 0)])
	await process_frame
	var near_a := {}
	for s in _bricks(a):
		if float(s.split(",")[0]) < 6.0:       # clear of A's clamped last bricks
			near_a[s] = true
	var in_b := {}
	for s in _bricks(b):
		in_b[s] = true
	var missing := 0
	for s in near_a:
		if not in_b.has(s):
			missing += 1
	_check(near_a.size() > 40, "stability: too few near-end bricks to compare (%d of %d)"
			% [near_a.size(), _bricks(a).size()])
	_check(missing == 0, "stability: %d/%d near-end bricks moved when the far end grew"
			% [missing, near_a.size()])
	a.free(); b.free()
	_done("stability")


## Posts stand at open ends and sharp corners; a closed loop gets corner posts, no end posts,
## and exactly one post at its seam.
func _post_suite() -> void:
	var straight := _wall([Vector3.ZERO, Vector3(8, 0, 0)])
	var ell := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 6)])
	var loop := _wall([Vector3.ZERO, Vector3(8, 0, 0), Vector3(8, 0, 6), Vector3(0, 0, 6),
			Vector3.ZERO])
	await process_frame
	_check(straight.stats.posts == 2, "posts: straight wall has %s posts, wanted 2"
			% str(straight.stats.posts))
	_check(ell.stats.posts == 3, "posts: L wall has %s posts, wanted 3" % str(ell.stats.posts))
	_check(loop.stats.posts == 4, "posts: closed square has %s posts, wanted 4 (3 corners + seam)"
			% str(loop.stats.posts))
	_check(loop.stats.runs == 4, "posts: closed square has %s runs, wanted 4"
			% str(loop.stats.runs))
	straight.free(); ell.free(); loop.free()
	_done("posts")


## No brick may stand inside an opening, and a door parts the collision while a window does not.
func _opening_suite() -> void:
	var w := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 2.7)
	var door := GladeOpening.new()
	door.position = Vector3(4, 0, 0)
	door.width = 1.6
	door.height = 2.2
	w.add_child(door)
	var win := GladeOpening.new()
	win.position = Vector3(9, 0, 0)
	win.width = 1.0
	win.height = 1.0
	win.sill_height = 1.2
	win.arched = false
	w.add_child(win)
	w.rebuild()
	await process_frame
	_check(w.stats.openings == 2, "openings: wall sees %s openings, wanted 2"
			% str(w.stats.openings))
	var invaders: Array[String] = []
	for s in _bricks(w):
		var parts := s.split(",")
		var x := float(parts[0])
		var y := float(parts[1])
		if absf(x - 4.0) < 0.5 and y < 2.0 and y > 0.1:
			invaders.append(s)                 # inside the door, well clear of arch/jambs
		if absf(x - 9.0) < 0.25 and y > 1.45 and y < 1.95:
			invaders.append(s)                 # inside the window hole
	_check(invaders.is_empty(), "openings: bricks inside an opening: %s" % str(invaders))
	# door passable at walking height, window still solid, lintel above the door still wall
	var boxes := _boxes(w)
	_check(not _point_in_boxes(boxes, w.to_global(Vector3(4, 1.0, 0))),
			"openings: door span is blocked")
	_check(_point_in_boxes(boxes, w.to_global(Vector3(9, 1.5, 0))),
			"openings: window hole opened the collision")
	# probe mid-lintel to either side of the door's centre — the centre itself sits exactly on
	# the shared boundary plane of two boxes, where float32 rounding can reject both
	_check(_point_in_boxes(boxes, w.to_global(Vector3(3.7, 2.45, 0)))
			and _point_in_boxes(boxes, w.to_global(Vector3(4.4, 2.45, 0))),
			"openings: no lintel collision above the door")

	# AN OPENING MUST MOVE BOTH WAYS. Sliding along the wall always worked; sliding UP it did
	# nothing, because the sill came only from sill_height and the node's own Y was ignored —
	# so the move gizmo appeared broken. Both axes now feed the wall.
	var slider := GladeOpening.new()
	slider.position = Vector3(6.5, 0.4, 0)
	slider.width = 1.2
	slider.height = 1.0
	slider.arched = false
	w.add_child(slider)
	w.rebuild()
	await process_frame
	var low_before := _hole_cells(w, 6.5, 0.5, 1.3)
	slider.position = Vector3(6.5, 1.9, 0)
	w.rebuild()
	await process_frame
	_check(low_before > 0, "openings: window made no hole at its starting height")
	_check(_hole_cells(w, 6.5, 0.5, 1.3) < low_before,
			"openings: dragging a window UP left the hole where it was")
	_check(_hole_cells(w, 6.5, 2.0, 2.8) > 0,
			"openings: dragging a window up did not open a hole higher on the wall")
	_check(absf(slider.effective_sill() - 1.9) < 0.01,
			"openings: effective sill is %.2f, wanted 1.9" % slider.effective_sill())
	w.free()
	_done("openings")


## Bricks missing near `at_x` within a height band — i.e. how much hole is there.
func _hole_cells(w: GladeWall, at_x: float, y0: float, y1: float) -> int:
	var holes := 0
	for i in 13:
		var x: float = at_x - 0.6 + i * 0.1
		var found := false
		for t in w.snap_transforms:
			if absf(t.origin.x - x) < 0.2 and t.origin.y > y0 and t.origin.y < y1:
				found = true
				break
		if not found:
			holes += 1
	return holes


## Collision hugs the wall: sampled points along the curve sit inside boxes, points beside it
## do not.
func _collision_suite() -> void:
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 8)])
	await process_frame
	var boxes := _boxes(w)
	_check(boxes.size() >= 2, "collision: only %d boxes for an L wall" % boxes.size())
	var holes := 0
	for f in [0.1, 0.3, 0.5, 0.7, 0.9]:
		var off: float = w.curve.get_baked_length() * f
		var p: Vector3 = w.curve.sample_baked(off)
		if not _point_in_boxes(boxes, w.to_global(p + Vector3.UP * 1.0)):
			holes += 1
	_check(holes == 0, "collision: %d/5 curve samples are uncovered" % holes)
	_check(not _point_in_boxes(boxes, w.to_global(Vector3(3, 1.0, 2.5))),
			"collision: box far off the wall line")
	w.free()
	_done("collision")


## Roofs cover the footprint, pitch correctly, and change how the wall finishes its top.
func _roof_suite() -> void:
	for hip in [false, true]:
		var w := _wall([Vector3(-3.5, 0, -2.5), Vector3(3.5, 0, -2.5), Vector3(3.5, 0, 2.5),
				Vector3(-3.5, 0, 2.5), Vector3(-3.5, 0, -2.5)], 2.6)
		var caps_before := 0
		for s in _bricks(w):
			if float(s.split(",")[1]) > 2.55:
				caps_before += 1
		var r := GladeRoof.new()
		r.hip = hip
		r.pitch_degrees = 38.0
		w.add_child(r)
		await process_frame
		await process_frame

		var tag := "hip" if hip else "gable"
		_check(int(r.stats.get("shingles", 0)) > 150,
				"roof(%s): only %s pieces" % [tag, str(r.stats.get("shingles"))])
		# ridge sits a full pitch above the eave: tan(38) * halfspan(2.5) = ~1.95
		var expect: float = 2.6 + tan(deg_to_rad(38.0)) * 2.5
		_check(absf(float(r.stats.ridge_y) - expect) < 0.05,
				"roof(%s): ridge at %.2f, wanted %.2f" % [tag, r.stats.ridge_y, expect])
		# ridge always runs the LONG way
		_check(float(r.stats.length) > float(r.stats.span),
				"roof(%s): ridge runs across the short axis" % tag)
		var lo := 999.0
		var hi := -999.0
		for t in r.snap_transforms:
			lo = minf(lo, t.origin.y)
			hi = maxf(hi, t.origin.y)
		_check(lo < 2.7 and hi > expect - 0.15,
				"roof(%s): pieces span %.2f..%.2f, expected eave..ridge" % [tag, lo, hi])
		# a hip has no gable walls; a gable does
		var gable_bricks := 0
		for t in r.snap_transforms:
			if absf(t.origin.x) > 3.3 and t.origin.y > 2.8:
				gable_bricks += 1
		if hip:
			_check(gable_bricks == 0, "roof(hip): %d gable-wall bricks on a hip" % gable_bricks)
		else:
			_check(gable_bricks > 0, "roof(gable): no gable-wall bricks")
		# ROOFED WALLS WEAR NO HAT: capstones and tall posts must vanish under a roof
		var caps_after := 0
		for s in _bricks(w):
			if float(s.split(",")[1]) > 2.55:
				caps_after += 1
		_check(caps_before > 0, "roof(%s): unroofed wall had no capstones to lose" % tag)
		_check(caps_after == 0,
				"roof(%s): %d bricks still above the eave under a roof" % [tag, caps_after])
		w.free()
	_done("roof")


## The weather brush paints INTENT, and the wall re-reads it: stains, then moss, then gaps.
## Crucially the paint is LOCAL — an untouched stretch of wall must not change at all.
func _weather_suite() -> void:
	var w := _wall([Vector3.ZERO, Vector3(20, 0, 0)], 3.0)
	await process_frame
	var clean := _bricks(w)
	var clean_far := {}
	for s in clean:
		if float(s.split(",")[0]) > 14.0:
			clean_far[s] = true
	_check(int(w.stats.moss) == 0, "weather: clean wall already has moss")

	# heavy weathering over the first few metres only
	for i in 8:
		w.paint_weather(2.0 + i * 0.35, 1.0 + (i % 3) * 0.5, 1.6, 0.9)
	w.rebuild()
	await process_frame
	var aged := _bricks(w)

	_check(int(w.stats.weathered_cells) > 20,
			"weather: only %s cells painted" % str(w.stats.weathered_cells))
	_check(int(w.stats.moss) > 0, "weather: no moss sprouted at amount 0.9")
	_check(aged.size() < clean.size(),
			"weather: nothing crumbled (%d bricks before, %d after)" % [clean.size(), aged.size()])
	# EDIT LOCALITY, again: the far end must be untouched, brick for brick
	var moved := 0
	var aged_set := {}
	for s in aged:
		aged_set[s] = true
	for s in clean_far:
		if not aged_set.has(s):
			moved += 1
	_check(clean_far.size() > 30, "weather: too few far bricks to compare")
	_check(moved == 0, "weather: %d/%d untouched bricks changed" % [moved, clean_far.size()])

	# NOTHING FLOATS. Masonry has no glue: every surviving stone must rest on another stone (or
	# on the ground). This is the invariant that forced erosion to eat COLUMNS from a break
	# upward instead of picking individual bricks.
	var floaters := 0
	for t in w.snap_transforms:
		if t.origin.y < 0.5:
			continue                          # bottom course, or rubble on the ground
		var supported := false
		for u in w.snap_transforms:
			var drop := t.origin.y - u.origin.y
			if drop > 0.06 and drop < 0.55 and absf(t.origin.x - u.origin.x) < 0.75:
				supported = true
				break
		if not supported:
			floaters += 1
	_check(floaters == 0, "weather: %d stones hang in mid-air" % floaters)

	# painting is stable and reversible
	var again := _bricks(w)
	_check(again == aged, "weather: rebuild after painting is not deterministic")
	w.clear_weather()
	w.rebuild()
	await process_frame
	_check(_bricks(w) == clean, "weather: clearing did not restore the original wall")
	w.free()
	_done("weather")


## The scatter brush: paint on a surface, get instances; paint elsewhere, disturb nothing.
func _scatter_suite() -> void:
	var ground := StaticBody3D.new()
	var shp := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shp.shape = box
	ground.add_child(shp)
	root.add_child(ground)
	ground.position = Vector3(0, -0.5, 0)
	await physics_frame

	var sc := GladeScatter.new()
	root.add_child(sc)
	await process_frame
	_check(int(sc.stats.get("instances", -1)) == 0, "scatter: unpainted node already has plants")

	for i in 6:
		sc.paint_at(Vector3(-6.0 + i * 0.5, 0.0, 0.0), Vector3.UP, 1.0, 0.9)
	sc.rebuild()
	await process_frame
	var first := sc.snap_transforms.duplicate()
	_check(first.size() > 20, "scatter: only %d instances after painting" % first.size())
	# everything sits on the painted surface, not floating above or buried
	var off := 0
	for t in first:
		if absf(t.origin.y) > 0.25:
			off += 1
	_check(off == 0, "scatter: %d instances are off the surface" % off)

	# EDIT LOCALITY: painting far away leaves the first patch untouched, instance for instance
	for i in 6:
		sc.paint_at(Vector3(8.0 + i * 0.5, 0.0, 4.0), Vector3.UP, 1.0, 0.9)
	sc.rebuild()
	await process_frame
	var kept := 0
	for t in first:
		for u in sc.snap_transforms:
			if t.origin.distance_to(u.origin) < 0.0005:
				kept += 1
				break
	_check(kept == first.size(),
			"scatter: %d/%d original plants moved when a distant patch was painted"
			% [first.size() - kept, first.size()])

	# deterministic, and erasing takes them away again
	var before_clear := sc.snap_transforms.size()
	sc.rebuild()
	await process_frame
	_check(sc.snap_transforms.size() == before_clear, "scatter: rebuild is not deterministic")
	sc.clear_scatter()
	sc.rebuild()
	await process_frame
	_check(sc.snap_transforms.is_empty(), "scatter: clearing left %d instances behind"
			% sc.snap_transforms.size())
	sc.free(); ground.free()
	_done("scatter")


## A plain timber style with round numbers, so the bay grid in the assertions below is exact.
func _timber_style(bay := 1.0) -> GladeStyle:
	var st: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	st.wall_mode = GladeStyle.WallMode.TIMBER
	st.bay_width = bay
	st.timber_size = 0.15
	st.end_posts = false                       # posts would inset the run and skew the bay grid
	st.corner_posts = false
	return st


## Is anything solid at (x, y) on a wall running along +X? Reads the CPU snapshot, treating each
## instance as the axis-aligned box its scale describes — true for every member of a straight
## timber wall except the braces, which are skipped: a diagonal's bounding box is far wider than
## the timber inside it, and would report a bay's neighbour as filling this bay.
func _solid_at(w: GladeWall, x: float, y: float) -> bool:
	for t in w.snap_transforms:
		if absf(t.basis.x.normalized().y) > 0.01:
			continue
		var s := t.basis.get_scale()
		if absf(t.origin.x - x) <= s.x * 0.5 and absf(t.origin.y - y) <= s.y * 0.5:
			return true
	return false


## The empty run of X containing `x` at height `y`, as [left, right]. Empty array if `x` is solid.
func _gap_around(w: GladeWall, x: float, y: float, lo: float, hi: float) -> Array:
	if _solid_at(w, x, y):
		return []
	var l := x
	while l > lo and not _solid_at(w, l, y):
		l -= 0.01
	var r := x
	while r < hi and not _solid_at(w, r, y):
		r += 0.01
	return [l, r]


func _storey(h: float, jetty := 0.0) -> GladeStorey:
	var s := GladeStorey.new()
	s.height = h
	s.jetty = jetty
	return s


## Mean Z of every brick whose centre lies in a height band. Mean, not max, because depth jitter
## is per-brick noise and averaging it away is the whole point of the comparison.
func _mean_z(w: GladeWall, y_lo: float, y_hi: float) -> float:
	var sum := 0.0
	var n := 0
	for t in w.snap_transforms:
		if t.origin.y >= y_lo and t.origin.y <= y_hi:
			sum += t.origin.z
			n += 1
	return sum / maxf(n, 1)


## STOREYS. Three claims, in order of how much they'd hurt to get wrong:
##   1. a flush stack IS the plain wall it replaces — otherwise adding storeys to the system would
##      silently redraw every wall anyone had already built;
##   2. a jetty actually steps the upper floor out, and hangs corbels under it;
##   3. edit locality survives the new axis — growing the top floor must not stir the ground floor.
func _storey_suite() -> void:
	var plain := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 4.8)
	var stacked := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 2.4)
	stacked.storeys = [_storey(2.4), _storey(2.4)]
	stacked.rebuild()
	await process_frame
	_check(absf(stacked.total_height() - 4.8) < 0.001,
			"storey: stack totals %.2f m, wanted 4.80" % stacked.total_height())
	_check(int(stacked.stats.storeys) == 2, "storey: stats report %s storeys, wanted 2"
			% str(stacked.stats.storeys))
	_check(_bricks(stacked) == _bricks(plain),
			"storey: a flush 2.4+2.4 stack differs from one 4.8 m wall (%d vs %d bricks)"
			% [_bricks(stacked).size(), _bricks(plain).size()])
	_check(int(stacked.stats.corbels) == 0, "storey: a flush stack grew corbels")

	# 2 — the upper floor oversails. The wall runs along X, so the step shows up in Z.
	var jettied := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 2.4)
	jettied.storeys = [_storey(2.4), _storey(2.4, 0.4)]
	jettied.rebuild()
	await process_frame
	var step := absf(_mean_z(jettied, 3.0, 4.6) - _mean_z(jettied, 0.2, 2.0))
	_check(absf(step - 0.4) < 0.06,
			"storey: jettied floor stands %.2f m proud, wanted 0.40" % step)
	_check(int(jettied.stats.corbels) > 4,
			"storey: a jetty grew only %s corbels" % str(jettied.stats.corbels))

	# 3 — edit locality across the stack
	var ground_before := {}
	for i in jettied.snap_transforms.size():
		var t: Transform3D = jettied.snap_transforms[i]
		if t.origin.y < 2.0:
			ground_before["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	jettied.storeys[1].height = 3.6
	jettied.rebuild()
	await process_frame
	var moved := 0
	var now := {}
	for t in jettied.snap_transforms:
		now["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	for k in ground_before:
		if not now.has(k):
			moved += 1
	_check(ground_before.size() > 100, "storey: too few ground-floor bricks to compare (%d)"
			% ground_before.size())
	_check(moved == 0, "storey: %d/%d ground-floor bricks moved when the floor above grew"
			% [moved, ground_before.size()])
	plain.free(); stacked.free(); jettied.free()
	_done("storey")


## TIMBER FRAME. A peer of masonry, not a special case of it, so the claims are the structural
## ones: bays tile the run with nothing missing, every boundary carries a stud, the plaster sits
## back behind the frame, braces lean, an opening lands between two studs instead of eating one,
## and the whole thing still holds edit locality when the run grows.
func _timber_suite() -> void:
	var st := _timber_style(1.0)
	var w := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 3.0)
	w.style = st
	w.rebuild()
	await process_frame
	_check(w.snap_transforms.size() > 40, "timber: only %d members framed"
			% w.snap_transforms.size())

	# plaster vs frame: lighter, and set BACK behind the timbers on both faces
	var panels := 0
	var proud := 0
	for i in w.snap_transforms.size():
		var c: Color = w.snap_colors[i]
		if c.get_luminance() > 0.6:
			panels += 1
			if w.snap_transforms[i].basis.get_scale().z > st.depth - 0.05:
				proud += 1
	_check(panels > 8, "timber: only %d plaster panels" % panels)
	_check(proud == 0, "timber: %d panels sit flush with the frame instead of behind it" % proud)

	# braces lean; nothing else does
	var leaning := 0
	for t in w.snap_transforms:
		if absf(t.basis.x.normalized().y) > 0.01:
			leaning += 1
	_check(leaning >= 2, "timber: %d braces, wanted at least the two end bays" % leaning)

	# BAYS TILE THE RUN. Panels and studs together leave no hole in an unbroken wall.
	# sampled off the bay boundaries on purpose: a sample landing exactly on a stud's edge is a
	# float coin-flip, not a gap, and would make this suite flaky rather than strict
	var holes: Array[String] = []
	for i in 96:
		var x := 0.13 + i * 0.1
		if not _solid_at(w, x, 0.6):
			holes.append("%.2f" % x)
	_check(holes.is_empty(), "timber: %d/96 samples fall through a gap between bays (at x=%s)"
			% [holes.size(), ", ".join(holes)])

	# a stud stands on every bay boundary
	var missing := 0
	for b in range(1, 10):
		var found := false
		for t in w.snap_transforms:
			var s := t.basis.get_scale()
			if absf(s.x - 0.15) < 0.02 and absf(t.origin.x - (b + 0.075)) < 0.02 \
					and s.y > 1.0:
				found = true
				break
		if not found:
			missing += 1
	_check(missing == 0, "timber: %d/9 bay boundaries have no stud" % missing)

	# OPENINGS SNAP TO BAYS. A door at 4.0 x 1.7 spans 3.15..4.85 unsnapped; snapped it runs from
	# the inner face of the stud at 3.0 to the boundary at 5.0, so both studs survive whole.
	var door := GladeOpening.new()
	door.position = Vector3(4, 0, 0)
	door.width = 1.7
	door.height = 2.2
	door.arched = false
	w.add_child(door)
	w.rebuild()
	await process_frame
	var gap := _gap_around(w, 4.0, 1.0, 0.0, 10.0)
	_check(gap.size() == 2, "timber: the door left no hole in the frame")
	if gap.size() == 2:
		_check(absf(gap[0] - 3.15) < 0.03 and absf(gap[1] - 5.0) < 0.03,
				"timber: door hole runs %.2f..%.2f, wanted 3.15..5.00" % [gap[0], gap[1]])

	# ...and the same door in MASONRY does not snap — proof the snapping is doing the work
	var mw := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 3.0)
	var mst: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	mst.end_posts = false
	mst.corner_posts = false
	mw.style = mst
	var door2 := GladeOpening.new()
	door2.position = Vector3(4, 0, 0)
	door2.width = 1.7
	door2.height = 2.2
	door2.arched = false
	mw.add_child(door2)
	mw.rebuild()
	await process_frame
	var mgap := _gap_around(mw, 4.0, 1.0, 0.0, 10.0)
	_check(mgap.size() == 2 and absf(mgap[1] - mgap[0] - 1.7) < 0.25,
			"timber: a masonry door moved too — the bay snap is not mode-gated")

	# EDIT LOCALITY across the new axis: lengthening the run must not reflow the bays already
	# framed at the other end.
	var short_w := _wall([Vector3.ZERO, Vector3(10, 0, 0)], 3.0)
	short_w.style = _timber_style(1.0)
	short_w.rebuild()
	var long_w := _wall([Vector3.ZERO, Vector3(16, 0, 0)], 3.0)
	long_w.style = _timber_style(1.0)
	long_w.rebuild()
	await process_frame
	var near := {}
	for s in _bricks(short_w):
		if float(s.split(",")[0]) < 8.0:
			near[s] = true
	var in_long := {}
	for s in _bricks(long_w):
		in_long[s] = true
	var moved := 0
	for s in near:
		if not in_long.has(s):
			moved += 1
	_check(near.size() > 30, "timber: too few near-end members to compare (%d)" % near.size())
	_check(moved == 0, "timber: %d/%d members moved when the run grew" % [moved, near.size()])

	w.free(); mw.free(); short_w.free(); long_w.free()
	_done("timber")


func _opening(w: GladeWall, at: float, sill: float, width: float, height: float) -> GladeOpening:
	var o := GladeOpening.new()
	o.position = Vector3(at, sill, 0)
	o.width = width
	o.height = height
	o.arched = false
	w.add_child(o)
	return o


## Every generated Node3D that is not part of the wall's own masonry — i.e. the socketed props.
func _props(w: GladeWall) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in w.get_children(true):
		if c is Node3D and not (c is MultiMeshInstance3D or c is StaticBody3D
				or c is CollisionShape3D or c is GladeOpening):
			out.append(c)
	return out


## PROP SOCKETS. The blocks are handcrafted; the rules decide which hole gets which block and how
## often. What has to hold: an empty socket grows nothing rather than erroring, a filled one
## lands the block ON the opening at the right size, doors and windows get different blocks, and
## the per-opening rolls are keyed to position so moving one window leaves its neighbour alone.
func _prop_suite() -> void:
	# 1 -- empty sockets: the old bare-hole behaviour, unchanged
	var bare := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	_opening(bare, 4.0, 1.0, 1.0, 1.0)
	bare.rebuild()
	await process_frame
	_check(int(bare.stats.props) == 0, "props: an empty socket grew %s props"
			% str(bare.stats.props))

	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_timber.tres")
	_check(stone != null and stone.window_frame != null,
			"props: alsace_stone.tres has no window frame wired up")
	_check(st != null and st.shutter != null,
			"props: alsace_timber.tres has no shutter wired up")

	# 2 -- a window gets a frame, scaled to the hole and standing on the wall's FACE.
	# Masonry on purpose: a timber wall would snap the opening to its bays first, and this
	# assertion is about prop placement, not about that.
	var w := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	w.style = stone
	_opening(w, 4.0, 1.2, 1.4, 1.1)
	w.rebuild()
	await process_frame
	var props := _props(w)
	_check(props.size() >= 1, "props: a window with a frame socket grew nothing")
	var frame: Node3D = null
	for p in props:
		var s := p.transform.basis.get_scale()
		if absf(s.x - 1.4) < 0.02 and absf(s.y - 1.1) < 0.02:
			frame = p
	_check(frame != null, "props: no prop is scaled to the opening's 1.40 x 1.10")
	if frame:
		_check(absf(frame.position.x - 4.0) < 0.05 and absf(frame.position.y - 1.2) < 0.05,
				"props: the frame sits at (%.2f, %.2f), wanted (4.00, 1.20)"
				% [frame.position.x, frame.position.y])
		# it must stand on the OUTER face, not buried in the middle of the wall
		_check(absf(frame.position.z) > 0.05,
				"props: the frame sits in the wall plane instead of on its face")

	# 2b -- and on a TIMBER wall the frame follows the opening to its snapped bay, rather than
	# staying behind where the author dropped it. The two rules have to agree.
	var tw := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	tw.style = st
	_opening(tw, 4.0, 1.2, 1.4, 1.1)
	tw.rebuild()
	await process_frame
	var tframe: Node3D = null
	for p in _props(tw):
		var s := p.transform.basis.get_scale()
		if s.x > 0.0 and absf(s.y - 1.1) < 0.02 and absf(s.x - s.z) > 0.05:
			tframe = p                          # the frame: scaled in x and y, not in z
	_check(tframe != null, "props: the timber wall grew no window frame")
	if tframe:
		var bay: float = st.bay_width
		var edge: float = tframe.position.x - tframe.transform.basis.get_scale().x * 0.5
		_check(absf(edge - (round(edge / bay) * bay + st.timber_size)) < 0.03,
				"props: the frame's left edge is at %.2f, not on a bay boundary + stud" % edge)

	# 3 -- a door draws from a different socket than a window
	var dw := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	dw.style = stone
	_opening(dw, 4.0, 0.0, 1.2, 2.1)
	dw.rebuild()
	await process_frame
	_check(int(dw.stats.props) >= 1, "props: a door grew nothing")
	var leaf: Node3D = null
	for p in _props(dw):
		var s := p.transform.basis.get_scale()
		if absf(s.x - 1.2) < 0.02 and absf(s.y - 2.1) < 0.02:
			leaf = p
	_check(leaf != null, "props: no prop is scaled to the door's 1.20 x 2.10")

	# 4 -- EDIT LOCALITY: moving one window must not re-roll the one beside it
	var mw := _wall([Vector3.ZERO, Vector3(20, 0, 0)], 3.0)
	mw.style = st
	var keep := _opening(mw, 4.0, 1.2, 1.2, 1.1)
	var move := _opening(mw, 12.0, 1.2, 1.2, 1.1)
	mw.rebuild()
	await process_frame
	var before := {}
	for p in _props(mw):
		if p.position.x < 8.0:
			before["%.3f,%.3f,%.3f|%s" % [p.position.x, p.position.y, p.position.z,
					str(p.transform.basis.get_scale().snappedf(0.001))]] = true
	_check(before.size() >= 1, "props: the kept window grew no props to compare")
	move.position.x = 14.5
	mw.rebuild()
	await process_frame
	var after := {}
	for p in _props(mw):
		after["%.3f,%.3f,%.3f|%s" % [p.position.x, p.position.y, p.position.z,
				str(p.transform.basis.get_scale().snappedf(0.001))]] = true
	var moved := 0
	for k in before:
		if not after.has(k):
			moved += 1
	_check(moved == 0, "props: %d/%d props on the untouched window changed when its neighbour"
			% [moved, before.size()] + " was dragged")
	# and the roll actually varies between positions, or "locality" would be vacuous
	var counts := {}
	for x in [2.0, 5.0, 8.0, 11.0, 14.0, 17.0]:
		var probe := _wall([Vector3.ZERO, Vector3(20, 0, 0)], 3.0)
		probe.style = st
		_opening(probe, x, 1.2, 1.2, 1.1)
		probe.rebuild()
		await process_frame
		counts[int(probe.stats.props)] = true
		probe.free()
	_check(counts.size() > 1,
			"props: every window in a row grew the same props -- the rolls are not position-keyed")

	bare.free(); w.free(); tw.free(); dw.free(); mw.free()
	_done("props")


func _house(span := 7.0, deep := 5.0, height := 2.6) -> GladeWall:
	return _wall([Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep),
			Vector3(0, 0, deep), Vector3.ZERO], height)


## DORMERS, CHIMNEYS AND EAVE BRACKETS. What has to hold: a dormer BITES a hole in the slope it
## stands on rather than sitting on top of the tiles; the tiles it does not displace are
## untouched (edit locality, on the roof this time); a chimney clears the ridge whatever the
## pitch; and an empty socket still grows nothing.
func _dormer_suite() -> void:
	var w := _house()
	var r := GladeRoof.new()
	r.pitch_degrees = 45.0
	r.eave_brackets = false                    # brackets are props, not shingles; tested apart
	w.add_child(r)
	await process_frame
	await process_frame
	var plain: int = int(r.stats.shingles)
	_check(plain > 150, "dormer: bare roof has only %d pieces" % plain)
	_check(int(r.stats.dormers) == 0, "dormer: a bare roof reports %s dormers"
			% str(r.stats.dormers))

	# 1 -- the evenly spaced row: two per long slope
	r.dormer_count = 2
	r.rebuild()
	await process_frame
	_check(int(r.stats.dormers) == 4, "dormer: dormer_count 2 gave %s dormers, wanted 4 (2 a side)"
			% str(r.stats.dormers))

	# 2 -- a hand-placed one ADDS to the row rather than replacing it
	var d := GladeDormer.new()
	d.position = Vector3(1.0, 0, -2.0)
	r.add_child(d)
	await process_frame
	await process_frame
	_check(int(r.stats.dormers) == 5,
			"dormer: a GladeDormer child gave %s total, wanted 5 (4 from the rule + 1 by hand)"
			% str(r.stats.dormers))

	# 3 -- a dormer BITES the slope rather than sitting on top of the tiles. The tiler counts
	# what it skipped, which is a direct reading of the behaviour instead of archaeology on
	# the output.
	r.dormer_count = 0
	d.enabled = false
	r.rebuild()
	await process_frame
	_check(int(r.stats.cut) == 0, "dormer: %s tiles cut with no dormer on the roof"
			% str(r.stats.cut))
	d.enabled = true
	r.rebuild()
	await process_frame
	_check(int(r.stats.cut) > 3, "dormer: only %s tiles displaced — the dormer sits ON the roof"
			% str(r.stats.cut))

	# 4 -- EDIT LOCALITY on the roof: the far end of the slope is untouched, tile for tile
	var far_before := {}
	for t in r.snap_transforms:
		if t.origin.x > 5.0:
			far_before["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	d.position.x = 2.4
	r.rebuild()
	await process_frame
	var now := {}
	for t in r.snap_transforms:
		now["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	var moved := 0
	for k in far_before:
		if not now.has(k):
			moved += 1
	_check(far_before.size() > 20, "dormer: too few far tiles to compare (%d)"
			% far_before.size())
	_check(moved == 0, "dormer: %d/%d tiles at the far end moved when a dormer slid along"
			% [moved, far_before.size()])

	# 5 -- a chimney clears the ridge, and clears it further on a steeper roof
	var ch := GladeChimney.new()
	ch.position = Vector3(1.4, 0, -1.2)
	ch.clearance = 0.8
	r.add_child(ch)
	await process_frame
	await process_frame
	_check(int(r.stats.chimneys) == 1, "dormer: %s chimneys, wanted 1" % str(r.stats.chimneys))
	var top := -999.0
	for t in r.snap_transforms:
		top = maxf(top, t.origin.y)
	_check(top > float(r.stats.ridge_y) + 0.5,
			"dormer: the stack tops out at %.2f, below ridge %.2f + clearance"
			% [top, r.stats.ridge_y])

	# 6 -- eave brackets come from a socket, and an empty socket grows none
	var w2 := _house()
	var r2 := GladeRoof.new()
	r2.style = load("res://addons/gladekit/styles/alsace_timber.tres")
	w2.add_child(r2)
	await process_frame
	await process_frame
	_check(int(r2.stats.brackets) > 4, "dormer: only %s eave brackets from a wired-up style"
			% str(r2.stats.brackets))
	var w3 := _house()
	var r3 := GladeRoof.new()
	r3.style = load("res://addons/gladekit/styles/crypt_stone.tres")
	w3.add_child(r3)
	await process_frame
	await process_frame
	_check(int(r3.stats.brackets) == 0,
			"dormer: a style with no eave_bracket socket grew %s brackets"
			% str(r3.stats.brackets))

	w.free(); w2.free(); w3.free()
	_done("dormers")


## Every interior angle of a closed footprint, in degrees.
func _corner_angles(w: GladeWall) -> Array[float]:
	var out: Array[float] = []
	var n := w.curve.point_count - 1
	for i in n:
		var prev := w.curve.get_point_position((i - 1 + n) % n)
		var here := w.curve.get_point_position(i)
		var next := w.curve.get_point_position((i + 1) % n)
		out.append(rad_to_deg((prev - here).normalized().angle_to((next - here).normalized())))
	return out


## BOX PLAN. A fence is a curve; a house is a volume, and dragging a house's wall must MOVE THAT
## WALL, not bow it. What has to hold: a box reads back as a box; pushing one face changes only
## the span across it and leaves the other one alone; every corner stays square after a face or
## corner drag; a box cannot be dragged inside out; and a bent footprint is correctly refused.
func _box_suite() -> void:
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 2.6)
	w.plan_mode = GladeWall.PlanMode.BOX
	await process_frame
	var p := w.box_plan()
	_check(p.ok, "box: a plain 6 x 5 rectangle did not read back as a box")
	if p.ok:
		_check(absf(p.w - 6.0) < 0.01 and absf(p.d - 5.0) < 0.01,
				"box: read back %.2f x %.2f, wanted 6.00 x 5.00" % [p.w, p.d])

	# 1 -- PUSH FACE 2 (the far one, at d) out to z = 7. Only the span across it may change; the
	# span along it, and the origin, must be exactly where they were.
	_check(w.push_face(2, Vector3(3.0, 0, 7.0)), "box: push_face refused a valid box")
	await process_frame
	var q := w.box_plan()
	_check(q.ok and absf(q.d - 7.0) < 0.01 and absf(q.w - 6.0) < 0.01,
			"box: after pushing one face it reads %.2f x %.2f, wanted 6.00 x 7.00" % [q.w, q.d])
	_check(q.origin.distance_to(p.origin) < 0.01,
			"box: pushing the far face moved the near one to %s" % str(q.origin))
	for a in _corner_angles(w):
		_check(absf(a - 90.0) < 0.5, "box: a corner is %.1f degrees after a face drag" % a)

	# 1b -- push the NEAR face (face 0): it carries the origin, so the origin moves and the span
	# shrinks by the same amount. The far wall must not budge.
	var far_before: Vector3 = q.origin + q.v * q.d
	_check(w.push_face(0, Vector3(3.0, 0, 1.5)), "box: push_face 0 refused")
	await process_frame
	var q2 := w.box_plan()
	_check(absf(q2.d - 5.5) < 0.01 and absf(q2.w - 6.0) < 0.01,
			"box: near-face drag gave %.2f x %.2f, wanted 6.00 x 5.50" % [q2.w, q2.d])
	_check((q2.origin + q2.v * q2.d).distance_to(far_before) < 0.01,
			"box: dragging the near wall dragged the far one with it")

	# 1c -- a face drag SNAPS, so buildings land on tidy numbers instead of 6.9137
	w.push_face(2, Vector3(3.0, 0, 7.13))
	await process_frame
	var snapped: float = w.box_plan().d
	_check(absf(snapped - snappedf(snapped, GladeWall.BOX_SNAP)) < 0.001,
			"box: a dragged face landed on %.4f, off the %.2f snap"
			% [snapped, GladeWall.BOX_SNAP])
	w.set_box_plan(p.origin, p.u, p.v, 6.0, 7.0)
	await process_frame

	# 1d -- pull a corner: the OPPOSITE corner is pinned and both adjacent walls follow
	var pinned: Vector3 = w.box_plan().origin + w.box_plan().u * 6.0 + w.box_plan().v * 7.0
	_check(w.pull_corner(0, Vector3(-2.0, 0, -1.0)), "box: pull_corner refused")
	await process_frame
	var q3 := w.box_plan()
	_check((q3.origin + q3.u * q3.w + q3.v * q3.d).distance_to(pinned) < 0.01,
			"box: pulling a corner moved the opposite one")
	_check(absf(q3.w - 8.0) < 0.01 and absf(q3.d - 8.0) < 0.01,
			"box: corner pull gave %.2f x %.2f, wanted 8.00 x 8.00" % [q3.w, q3.d])
	for a in _corner_angles(w):
		_check(absf(a - 90.0) < 0.5, "box: a corner is %.1f degrees after a corner pull" % a)

	# 1e -- a corner cannot be dragged through its opposite
	w.pull_corner(0, pinned)
	await process_frame
	var q4 := w.box_plan()
	_check(q4.ok and q4.w >= GladeWall.MIN_BOX_SIDE - 0.001
			and q4.d >= GladeWall.MIN_BOX_SIDE - 0.001,
			"box: a corner dragged onto its opposite collapsed the box to %.2f x %.2f"
			% [q4.w, q4.d])
	w.set_box_plan(p.origin, p.u, p.v, 6.0, 7.0)
	await process_frame

	# 2 -- and the WALL really is bigger, not just the intent
	_check(absf(w.curve.get_baked_length() - 2.0 * (6.0 + 7.0)) < 0.05,
			"box: perimeter is %.2f, wanted %.2f (started at %.2f)"
			% [w.curve.get_baked_length(), 2.0 * (6.0 + 7.0), 2.0 * (6.0 + 5.0)])
	w.rebuild()
	await process_frame
	_check(int(w.stats.runs) == 4, "box: %s runs after a face drag, wanted 4" % str(w.stats.runs))
	var reach := -99.0
	for t in w.snap_transforms:
		reach = maxf(reach, t.origin.z)
	_check(reach > 6.5, "box: bricks only reach z=%.2f after the wall was dragged to 7.00"
			% reach)

	# 3 -- a box cannot be turned inside out
	w.set_box_plan(p.origin, p.u, p.v, 0.05, -3.0)
	await process_frame
	var r := w.box_plan()
	_check(r.ok and r.w >= GladeWall.MIN_BOX_SIDE - 0.001
			and r.d >= GladeWall.MIN_BOX_SIDE - 0.001,
			"box: collapsed to %.2f x %.2f, below the %.2f floor"
			% [r.w, r.d, GladeWall.MIN_BOX_SIDE])

	# 4 -- make_box replaces any footprint with a clean rectangle in BOX mode
	var odd := _wall([Vector3.ZERO, Vector3(4, 0, 1), Vector3(7, 0, 4), Vector3(2, 0, 6),
			Vector3.ZERO], 2.6)
	await process_frame
	_check(not odd.box_plan().ok, "box: a skewed footprint wrongly read back as a box")
	odd.make_box(5.0, 4.0)
	await process_frame
	var o := odd.box_plan()
	_check(o.ok and absf(o.w - 5.0) < 0.01 and absf(o.d - 4.0) < 0.01,
			"box: make_box gave %s" % str(o))
	_check(odd.plan_mode == GladeWall.PlanMode.BOX, "box: make_box left the wall in FREE mode")

	# 5 -- a BENT wall is not a box, so face pearls must never claim it
	var bent := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 2.6)
	bent.curve.set_point_out(0, Vector3(0, 0, -2))
	bent.curve.set_point_in(1, Vector3(0, 0, -2))
	await process_frame
	# the corners are still square, but the curve now bulges — box_plan only inspects corners, so
	# this documents the limit rather than pretending otherwise
	_check(bent.box_plan().ok, "box: a bulged rectangle still reads by its corners")
	# ...and switching to BOX and writing a plan straightens it, which is the escape hatch
	var bp := bent.box_plan()
	bent.set_box_plan(bp.origin, bp.u, bp.v, bp.w, bp.d)
	await process_frame
	_check(bent.curve.get_point_out(0).length() < 0.001,
			"box: set_box_plan left a stale control point, so the wall stays bowed")

	w.free(); odd.free(); bent.free()
	_done("box plan")


## Crenellations: merlons with gaps between them, sitting above the wall top.
func _battlement_suite() -> void:
	var plain := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	var st: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	st.crenellated = true
	st.band_every = 1.5
	var castle := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	castle.style = st
	castle.rebuild()
	await process_frame

	# sample the top band across the wall: merlons leave gaps, a cap course does not
	var gaps := 0
	var solid := 0
	for i in 60:
		var x := 1.0 + i * 0.17
		var found := false
		for t in castle.snap_transforms:
			if absf(t.origin.x - x) < 0.12 and t.origin.y > 3.05:
				found = true
				break
		if found:
			solid += 1
		else:
			gaps += 1
	_check(gaps > 8 and solid > 8,
			"battlements: %d gaps / %d merlon samples — not alternating" % [gaps, solid])
	var plain_top := 0
	for t in plain.snap_transforms:
		if t.origin.y > 3.05:
			plain_top += 1
	_check(plain_top > 0, "battlements: plain wall lost its cap course")
	# band courses jut out further than the wall face
	var banded := 0
	for t in castle.snap_transforms:
		if absf(t.origin.y - 1.5) < 0.2 and t.basis.get_scale().z > st.depth + 0.1:
			banded += 1
	_check(banded > 5, "battlements: only %d band-course bricks at 1.5 m" % banded)
	plain.free(); castle.free()
	_done("battlements")


## drop_to_ground lands curve points on terrain — and never on the wall's OWN collision, which
## would make a wall climb itself every time the button is pressed.
func _drop_suite() -> void:
	var ground := StaticBody3D.new()
	var shp := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 2, 40)
	shp.shape = box
	ground.add_child(shp)
	root.add_child(ground)
	ground.position = Vector3(0, 1.5, 0)       # top surface at y = 2.5
	await physics_frame
	await physics_frame

	var w := _wall([Vector3.ZERO, Vector3(8, 0, 0)], 2.0)
	w.position = Vector3(0, 6, 0)              # floating well above the slab
	await process_frame
	_check(w.drop_to_ground(), "drop: nothing moved")
	await process_frame
	for i in w.curve.point_count:
		var y: float = w.to_global(w.curve.get_point_position(i)).y
		_check(absf(y - 2.5) < 0.05, "drop: point %d landed at y=%.2f, wanted 2.5" % [i, y])
	# idempotent: a second drop must not climb the wall's own bricks
	w.drop_to_ground()
	await process_frame
	var y2: float = w.to_global(w.curve.get_point_position(0)).y
	_check(absf(y2 - 2.5) < 0.05, "drop: second drop climbed to y=%.2f" % y2)
	w.free(); ground.free()
	_done("drop")


## GladePath: paving generates, and it is deterministic like everything else.
func _path_suite() -> void:
	var a := GladePath.new()
	var ca := Curve3D.new()
	ca.add_point(Vector3.ZERO)
	ca.add_point(Vector3(10, 0, 4))
	a.curve = ca
	root.add_child(a)
	var b := GladePath.new()
	b.curve = ca.duplicate()
	root.add_child(b)
	await process_frame
	_check(int(a.stats.stones) > 20, "path: only %s stones" % str(a.stats.get("stones")))
	_check(a.snap_transforms == b.snap_transforms and a.snap_colors == b.snap_colors,
			"path: identical paths differ")
	a.free(); b.free()
	_done("path")


## The signature interaction: a path drawn THROUGH a wall parts it — an arch in a tall wall, a
## full gap in a low one — and deleting the path heals the wall.
func _crossing_suite() -> void:
	var wall := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0)
	var low := _wall([Vector3(0, 0, 6), Vector3(12, 0, 6)], 1.2)
	var path := GladePath.new()
	var pc := Curve3D.new()
	pc.add_point(Vector3(6, 0, -3))
	pc.add_point(Vector3(6, 0, 9))              # crosses BOTH walls
	path.curve = pc
	root.add_child(path)
	await process_frame
	await process_frame                          # path pokes walls; their rebuilds are deferred

	_check(int(wall.stats.openings) == 1, "crossing: tall wall sees %s openings, wanted 1"
			% str(wall.stats.get("openings")))
	_check(int(low.stats.openings) == 1, "crossing: low wall sees %s openings, wanted 1"
			% str(low.stats.get("openings")))
	# tall wall: passable arch, wall continues above (bricks over the opening)
	var above := 0
	var inside := 0
	for s in _bricks(wall):
		var parts := s.split(",")
		var x := float(parts[0])
		var y := float(parts[1])
		if absf(x - 6.0) < 0.8 and y > 2.35:
			above += 1
		if absf(x - 6.0) < 0.7 and y > 0.1 and y < 1.9:
			inside += 1
	_check(above > 0, "crossing: tall wall has nothing above the archway")
	_check(inside == 0, "crossing: %d bricks inside the tall wall's archway" % inside)
	_check(not _point_in_boxes(_boxes(wall), wall.to_global(Vector3(6, 1.0, 0))),
			"crossing: tall wall still blocks the path")
	# low wall: a full gap — nothing left standing in the crossing band, caps included
	var low_left := 0
	for s in _bricks(low):
		var parts := s.split(",")
		if absf(float(parts[0]) - 6.0) < 0.7:
			low_left += 1
	_check(low_left == 0, "crossing: %d bricks left in the low wall's gap" % low_left)

	# delete the path -> walls heal
	path.free()
	await process_frame
	await process_frame
	_check(int(wall.stats.openings) == 0, "crossing: wall did not heal after the path died")
	wall.free(); low.free()
	_done("crossing")


## conform_to_ground: over a dropped floor the wall's base steps DOWN in course multiples.
func _ground_suite() -> void:
	var floor_lo := StaticBody3D.new()
	var shp := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shp.shape = box
	floor_lo.add_child(shp)
	root.add_child(floor_lo)
	floor_lo.position = Vector3(14, -1.4, 0)   # top at -0.9 under the far half of the wall
	await physics_frame
	await physics_frame

	var w := _wall([Vector3.ZERO, Vector3(20, 0, 0)], 1.8)
	w.conform_to_ground = true
	w.rebuild()
	await process_frame
	var lows := 0
	for s in _bricks(w):
		var parts := s.split(",")
		if float(parts[0]) > 15.0 and float(parts[1]) < -0.4:
			lows += 1
	_check(lows > 10, "ground: only %d bricks stepped down over the sunken floor" % lows)
	w.free(); floor_lo.free()
	_done("ground")


# --- junctions and primitives ----------------------------------------------------------------
#
# Everything below pins the work that fixed docs/images/errors/*.png. Each suite carries its own
# CONTROL where it can — a measurement that only means something if it would have failed before.


func _styled(points: Array, st: GladeStyle, height := 2.4, seed_v := 7) -> GladeWall:
	var w := GladeWall.new()
	var c := Curve3D.new()
	for p: Vector3 in points:
		c.add_point(p)
	w.curve = c
	w.style = st
	w.rng_seed = seed_v
	w.wall_height = height
	w.generate_collision = false
	root.add_child(w)
	return w


## How many of this wall's brick boxes contain a point. 0 = a hole, 2+ = stone through stone.
func _pieces_at(w: GladeWall, p: Vector3) -> int:
	var n := 0
	for t in w.snap_transforms:
		var l := t.affine_inverse() * p
		if absf(l.x) <= 0.5 and absf(l.y) <= 0.5 and absf(l.z) <= 0.5:
			n += 1
	return n


## Sample the corner box of an L turning +X -> +Z at (4,0,0). Returns [double-claimed, empty].
## Sampled at COURSE CENTRES: a point on the shared face of two stacked members counts in both and
## reads as a false overlap — the same float coin-flip the timber suite samples away from.
func _corner_probe(w: GladeWall, st: GladeStyle) -> Array:
	var h: float = st.depth * 0.5
	var dbl := 0
	var holes := 0
	var steps := 9
	for ci in [3, 4, 5]:
		var y: float = ci * st.course_height + st.course_height * 0.5
		for ix in steps:
			for iz in steps:
				var p := Vector3(4.0 - h + 2.0 * h * (float(ix) + 0.5) / steps, y,
						-h + 2.0 * h * (float(iz) + 0.5) / steps)
				var n := _pieces_at(w, p)
				if n >= 2:
					dbl += 1
				elif n == 0:
					holes += 1
	return [dbl, holes]


## THE CORNER. Two runs meeting at a right angle used to overlap on the inside of the turn and
## leave a notch on the outside, because the curve is the wall's CENTRELINE and neither run did
## anything about the box they share. docs/images/errors/wall_rock_junction.png.
func _corner_suite() -> void:
	var l := [Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4)]
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var off: GladeStyle = st.duplicate()
	off.corner_mitre = false

	var before := _corner_probe(_styled(l, off, 2.4), st)
	_check(before[0] > 0, "corner CONTROL: unmitred corners should drive stone through stone")
	_check(before[1] > 0, "corner CONTROL: unmitred corners should leave an outer notch")

	var w := _styled(l, st, 2.4)
	var after := _corner_probe(w, st)
	_check(int(w.stats.get("quoins", 0)) > 0, "corner: the corner box was left unfilled")
	_check(after[0] == 0, "corner: %d samples still have stone through stone" % after[0])
	_check(after[1] == 0, "corner: %d samples of the outer corner are still empty" % after[1])

	# Quoins alternate along each wall as they rise — what makes a corner read as toothed.
	# SORT BY HEIGHT FIRST. snap_transforms concatenates one array per brick variant, so its order
	# is emission order only while there is a single variant; give the style a handful of
	# handcrafted brick meshes and the quoins arrive grouped by which mesh they drew, at which
	# point reading alternation straight off the array order is meaningless.
	var quoins: Array[Transform3D] = []
	for t in w.snap_transforms:
		if absf(t.origin.x - 4.0) < 0.02 and absf(t.origin.z) < 0.02:
			quoins.append(t)
	quoins.sort_custom(func(p, q): return p.origin.y < q.origin.y)
	var dirs: Array[String] = []
	for t in quoins:
		dirs.append("x" if absf(t.basis.x.normalized().x) > 0.7 else "z")
	var flips := 0
	for i in range(1, dirs.size()):
		if dirs[i] != dirs[i - 1]:
			flips += 1
	_check(dirs.size() >= 4 and flips >= dirs.size() - 2,
			"corner: quoins do not alternate (%d stones, %d flips)" % [dirs.size(), flips])

	# A TIMBER corner gets one post of the full wall section, not both runs' end studs fighting.
	var ts: GladeStyle = load("res://addons/gladekit/styles/alsace_timber.tres")
	var box := [Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4), Vector3.ZERO]
	var t_off: GladeStyle = ts.duplicate()
	t_off.corner_mitre = false
	var t_before := _corner_probe(_styled(box, t_off, 2.6), ts)
	var tw := _styled(box, ts, 2.6)
	var t_after := _corner_probe(tw, ts)
	_check(t_before[0] > 0, "corner CONTROL: unmitred timber corners should clash")
	_check(t_after[0] == 0, "corner: timber members still clash (%d)" % t_after[0])
	_check(t_after[1] == 0, "corner: the timber corner box is not solid (%d)" % t_after[1])
	var orients := {}
	for t in tw.snap_transforms:
		if absf(t.origin.x - 4.0) < 0.03 and absf(t.origin.z) < 0.03:
			orients["x" if absf(t.basis.x.normalized().x) > 0.7 else "z"] = true
	_check(orients.size() == 1,
			"corner: the timber corner is %d posts, not one" % orients.size())

	# A JETTIED corner. Each wall is pushed out along ITS OWN normal, so their corner moves to
	# where the two displaced lines cross — jetty * sqrt(2) out on the diagonal at a square corner.
	# Offsetting the post along just one of the normals (which is what it used to do) left it a
	# whole jetty inside the building, with the pale end of the plaster showing through the gap.
	var jet := _styled(box, ts, 2.4, 7)
	var s_low := GladeStorey.new()
	s_low.height = 2.4
	s_low.style = ts
	var s_high := GladeStorey.new()
	s_high.height = 2.4
	s_high.jetty = 0.3
	s_high.style = ts
	jet.storeys = [s_low, s_high]
	jet.rebuild()
	await process_frame
	# The post is the one member that runs the WHOLE storey — a rail is thin, a stud is short.
	var found := false
	var span := 0.0
	var centre_off := -1.0
	for t in jet.snap_transforms:
		var sc := t.basis.get_scale()
		if sc.y < 2.0 or t.origin.y < 2.8 or t.origin.y > 4.4:
			continue
		var dist := Vector2(t.origin.x - 4.0, t.origin.z).length()
		if dist > 1.0:
			continue
		found = true
		span = maxf(sc.x, sc.z)
		centre_off = dist
	_check(found, "corner: no post found at the jettied corner")
	# it stretches from the run's stopping point out to the corner's outer face: depth + the jetty
	_check(found and absf(span - (ts.depth + 0.3)) < 0.06,
			"corner: the jettied post spans %.3f m, should be %.3f (a bare depth of %.2f leaves a slot)"
					% [span, ts.depth + 0.3, ts.depth])
	# ...and sits centred BETWEEN the two runs' ends, which is half the corner's own displacement
	_check(found and absf(centre_off - 0.3 * sqrt(2.0) * 0.5) < 0.06,
			"corner: the jettied post is centred %.3f m off the corner, should be %.3f"
					% [centre_off, 0.3 * sqrt(2.0) * 0.5])

	# ...and being in the right PLACE is not enough. The runs still stop on the unjettied mitre
	# line, so a d x d post at the moved corner leaves a slot the width of the jetty down both
	# walls. Walk the displaced centreline of the arm that arrives, from well inside the run out to
	# the corner's outer face, and there must be no gap anywhere along it.
	var worst_gap := 0.0
	var gap_run := 0.0
	var x := 3.0
	while x < 4.46:
		if _pieces_at(jet, Vector3(x, 3.0, -0.30)) == 0:
			gap_run += 0.02
			worst_gap = maxf(worst_gap, gap_run)
		else:
			gap_run = 0.0
		x += 0.02
	_check(worst_gap < 0.08,
			"corner: a %.2f m slot is open between the jettied run and its corner post" % worst_gap)
	_done("corner")


## THE WINDOW. `_course_spans` only ever cut sideways, so an opening deleted a plaster panel over
## its whole rail-to-rail height and the hole came out far bigger than the window that made it.
## docs/images/errors/wall_window_junction.png.
func _jamb_suite() -> void:
	const AT := 2.0
	const SILL := 1.1
	const HGT := 1.0
	var ts: GladeStyle = load("res://addons/gladekit/styles/alsace_timber.tres")

	# CONTROL at the unit level: the old sideways-only cut against the new two-axis one, same input.
	var probe := _styled([Vector3.ZERO, Vector3(6, 0, 0)], ts, 2.6)
	var op := [{"at": AT, "w": 1.0, "h": HGT, "sill": SILL, "arched": false, "node": null}]
	var full := 6.0 * (2.45 - 1.20)
	var old_left := 0.0
	var new_left := 0.0
	for s in probe._course_spans(0.0, 6.0, 1.20, 2.45, op):
		old_left += (s[1] - s[0]) * (2.45 - 1.20)
	for r in probe._clear_rects(0.0, 6.0, 1.20, 2.45, op):
		new_left += (r[1] - r[0]) * (r[3] - r[2])
	_check(full - old_left > 1.0,
			"jamb CONTROL: the old cut should remove far more than the window (%.2f m2)"
					% (full - old_left))
	_check(full - new_left < 1.1,
			"jamb: the new cut removes %.2f m2 for a 1.0 x 1.0 window" % (full - new_left))

	# ...and end to end: the hole through the middle of the window must BE the window
	var w := _styled([Vector3.ZERO, Vector3(6, 0, 0)], ts, 2.6)
	var o := GladeOpening.new()
	o.position = Vector3(AT, SILL, 0)
	o.width = 1.0
	o.height = HGT
	o.arched = false
	w.add_child(o)
	w.rebuild()
	await process_frame
	var hole := _hole_span(w, AT, SILL + HGT * 0.5)
	_check(hole[1] - hole[0] < HGT + 0.55,
			"jamb: the hole is %.2f m tall for a %.2f m window" % [hole[1] - hole[0], HGT])
	_check(_pieces_at(w, Vector3(AT, 0.45, 0.0)) > 0, "jamb: no wall below the window")
	_check(_pieces_at(w, Vector3(AT, 2.35, 0.0)) > 0, "jamb: no wall above the window")

	# A DRESSED masonry opening lands on the window's own edges instead of on course lines.
	var ms: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var bare: GladeStyle = ms.duplicate()
	bare.opening_sill = false
	bare.opening_head = false
	var wb := _opening_wall(bare, AT, SILL, HGT)
	var wd := _opening_wall(ms, AT, SILL, HGT)
	await process_frame
	_check(int(wb.stats.get("lining", 0)) == 0, "jamb: lining off should grow nothing")
	_check(int(wd.stats.get("lining", 0)) > 0, "jamb: a dressed opening grew no sill or lintel")
	var eb := _hole_err(wb, AT, SILL, HGT)
	var ed := _hole_err(wd, AT, SILL, HGT)
	_check(ed < eb, "jamb: dressing did not tighten the hole (%.2f -> %.2f)" % [eb, ed])
	_check(ed < 0.10, "jamb: the dressed hole is %.2f m off the window" % ed)
	_done("jamb")


func _opening_wall(st: GladeStyle, at: float, sill: float, hgt: float) -> GladeWall:
	var w := _styled([Vector3.ZERO, Vector3(6, 0, 0)], st, 2.6)
	var o := GladeOpening.new()
	o.position = Vector3(at, sill, 0)
	o.width = 1.0
	o.height = hgt
	o.arched = false
	w.add_child(o)
	w.rebuild()
	return w


## The CONTIGUOUS empty run through a point — that run is "the hole". Taking every empty sample
## instead would fold in the hairline seams between stacked members.
func _hole_span(w: GladeWall, at: float, from_y: float) -> Array:
	var lo := from_y
	var hi := from_y
	while lo > 0.05 and _pieces_at(w, Vector3(at, lo - 0.04, 0.0)) == 0:
		lo -= 0.04
	while hi < 2.55 and _pieces_at(w, Vector3(at, hi + 0.04, 0.0)) == 0:
		hi += 0.04
	return [lo, hi]


func _hole_err(w: GladeWall, at: float, sill: float, hgt: float) -> float:
	var h := _hole_span(w, at, sill + hgt * 0.5)
	return absf(h[0] - sill) + absf(h[1] - (sill + hgt))


## Is any roof piece over this point? The in-plane tolerance is the MORTAR SEAM: tiles are laid
## `gap` apart, so a sample landing in a seam finds nothing and reads as a hole — about 4% of
## samples. A real hole is a whole tile across, so this cannot hide one.
func _roof_covered(r: GladeRoof, p: Vector3) -> bool:
	for t in r.snap_transforms:
		if t.origin.distance_to(p) > 1.2:
			continue
		# absf() on every scale component. Basis.get_scale() reports a NEGATIVE component for a
		# mirrored basis, so maxf(s.x, 0.001) collapsed to 0.001 and blew the tolerance out to 50 —
		# every sample near a mirrored tile counted as covered no matter where it was. That is how
		# this suite reported a fully shingled roof while a third of it was inside-out.
		var s := t.basis.get_scale().abs()
		var l := t.affine_inverse() * p
		if absf(l.x) <= 0.5 + 0.05 / maxf(s.x, 0.001) \
				and absf(l.z) <= 0.5 + 0.05 / maxf(s.z, 0.001) \
				and absf(l.y) <= 0.5 + 0.16 / maxf(s.y, 0.001):
			return true
	return false


## THE DORMER. Its cut used to be a full-width rectangle all the way back to where its ridge dies
## into the slope — but its own roof narrows to a point back there, so two triangles of shingle
## were removed that nothing ever covered again. docs/images/errors/roof_window_junction.png.
func _dormer_cut_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _styled([Vector3.ZERO, Vector3(7, 0, 0), Vector3(7, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], st, 2.6, 5)
	var r := GladeRoof.new()
	r.rng_seed = 3
	r.dormer_count = 1
	r.dormer_width = 1.2
	r.dormer_height = 0.9
	w.add_child(r)
	r.rebuild()
	await process_frame

	var ctx: Dictionary = r._plan(w.roof_host())   # the roof takes a HOST now, not a wall
	_check(int(r.stats.get("cut", 0)) > 0, "dormer_cut: the dormer stopped biting the slope")

	# Nowhere on either slope may be bald — EXCEPT inside a dormer's own cut, where the main slope
	# is legitimately open and the dormer covers the hole from above rather than at that plane.
	# Sampling the plane under a dormer and calling it a hole is measuring the wrong surface; the
	# over-cut assertion further down is what actually pins the dormer fix.
	var all_cuts: Dictionary = {-1.0: [], 1.0: []}
	for d in r._collect_dormers(ctx):
		(all_cuts[float(d.side)] as Array).append(d.cut)
	var bald := 0
	for side: float in [-1.0, 1.0]:
		for iu in 26:
			for iv in 16:
				var u := -0.96 + 1.92 * float(iu) / 25.0
				var v := 0.03 + 0.90 * float(iv) / 15.0
				if GladeRoof._in_cut(all_cuts[side], (u + 1.0) * 0.5, v):
					continue
				if not _roof_covered(r, r._slope_pt(ctx, side, u, v)):
					bald += 1
	_check(bald == 0, "dormer_cut: %d samples of bare slope" % bald)

	# CONTROL: the old rectangle removed strictly more than the dormer covers, and every point in
	# that over-cut region — the two triangles — must now carry shingle.
	var ds: Array = r._collect_dormers(ctx)
	var over := 0
	var still_open := 0
	for d in ds:
		var cut: Dictionary = d.cut
		var flat := cut.duplicate()
		flat.v_taper = flat.v1                 # no taper == the old rectangle
		for iu in 40:
			for iv in 30:
				var u := float(iu) / 39.0
				var v := float(iv) / 29.0
				if GladeRoof._in_cut([cut], u, v) or not GladeRoof._in_cut([flat], u, v):
					continue
				over += 1
				if not _roof_covered(r, r._slope_pt(ctx, float(d.side), u * 2.0 - 1.0, v)):
					still_open += 1
	_check(over > 0, "dormer_cut CONTROL: the old rectangle should over-cut the slope")
	_check(still_open == 0,
			"dormer_cut: %d/%d samples of the over-cut triangles are still open"
					% [still_open, over])

	# NO MIRRORED TILES. A negative-determinant basis does not tilt an instance, it mirrors it: the
	# winding flips, the front faces become back faces, culling removes them and you look into the
	# inside of every shingle. `Basis(x, y, z)` is right-handed only when x cross y == z, and the
	# natural spelling — cross two edges for a normal, then flip the normal to point up — gets it
	# wrong for exactly half the cases, which is why one slope of a gable was inside-out and the
	# other was fine. Measured before the fix: 33% of the main roof, 42% of the porch, 0% of walls.
	var mirrored := 0
	for t in r.snap_transforms:
		if t.basis.determinant() < 0.0:
			mirrored += 1
	_check(mirrored == 0, "dormer_cut: %d/%d roof instances are mirrored (left-handed basis)"
			% [mirrored, r.snap_transforms.size()])
	_done("dormer_cut")


## THE TOWER. A round footprint could not be authored and could not be roofed — a cylinder wall
## got a box fitted to it and a gable put on top.
func _cylinder_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.style = st
	w.rng_seed = 4
	w.wall_height = 5.0
	w.generate_collision = false
	root.add_child(w)
	w.make_cylinder(2.2, 20)
	w.rebuild()
	await process_frame

	var p := w.cylinder_plan()
	_check(p.ok, "cylinder: the footprint does not read back as a tower")
	_check(absf(float(p.radius) - 2.2) < 0.01, "cylinder: radius did not round-trip")
	_check(int(p.segments) == 20, "cylinder: segment count did not round-trip")
	_check(w._is_closed(), "cylinder: the tower does not close")
	# 18 degrees a vertex is under corner_angle_deg, so a smooth tower is ONE run, not twenty
	_check(int(w.stats.get("runs", 0)) == 1,
			"cylinder: a smooth tower came out as %d runs" % int(w.stats.get("runs", 0)))
	var worst := 0.0
	for t in w.snap_transforms:
		worst = maxf(worst, absf(Vector2(t.origin.x, t.origin.z).length() - 2.2))
	_check(worst < 0.35, "cylinder: a stone sits %.2f m off the tower's circle" % worst)

	# an OCTAGONAL tower turns sharply enough to be corners, and gets mitred and quoined for free
	var w8 := GladeWall.new()
	w8.style = st
	w8.rng_seed = 4
	w8.wall_height = 4.0
	w8.generate_collision = false
	root.add_child(w8)
	w8.make_cylinder(1.8, 8)
	w8.rebuild()
	await process_frame
	_check(int(w8.stats.get("runs", 0)) == 8,
			"cylinder: an octagon came out as %d runs" % int(w8.stats.get("runs", 0)))
	_check(int(w8.stats.get("quoins", 0)) > 0,
			"cylinder: an octagonal tower did not quoin its corners")
	_done("cylinder")


## A spire over a round tower, auto-detected, tiled by the same function a hip end uses.
func _roof_shape_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.style = st
	w.rng_seed = 4
	w.wall_height = 5.0
	w.generate_collision = false
	root.add_child(w)
	w.make_cylinder(2.2, 20)
	var r := GladeRoof.new()
	r.rng_seed = 2
	r.pitch_degrees = 52.0
	w.add_child(r)
	r.rebuild()
	await process_frame

	_check(r.stats.get("shape", "") == "cone", "roof_shape: a round tower was not given a spire")
	_check(int(r.stats.get("shingles", 0)) > 200,
			"roof_shape: the spire is only %d shingles" % int(r.stats.get("shingles", 0)))
	var apex := 0.0
	for t in r.snap_transforms:
		apex = maxf(apex, t.origin.y)
	var lo_r := 0.0
	var hi_r := 0.0
	for t in r.snap_transforms:
		var rad := Vector2(t.origin.x, t.origin.z).length()
		if t.origin.y < 5.2:
			lo_r = maxf(lo_r, rad)
		if t.origin.y > apex - 0.8:
			hi_r = maxf(hi_r, rad)
	_check(lo_r > 2.0, "roof_shape: the spire is not wide at the eave (%.2f)" % lo_r)
	_check(hi_r < lo_r * 0.4, "roof_shape: the spire does not narrow (%.2f -> %.2f)" % [lo_r, hi_r])
	_check(apex > 7.0, "roof_shape: the apex is only %.2f m up" % apex)
	_done("roof_shape")


## TWO SEPARATE BUILDINGS sharing space. Both halves matter, and the second one more:
## the loser's stone inside the winner is gone, AND the winner is byte-identical to standing alone.
func _junction_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5), Vector3.ZERO]

	var solo_t := _junc_tower(st, Vector3(100, 0, 100), 5)
	var solo_sig := _bricks(solo_t)
	var solo_b := _styled(plan, st, 3.0, 9)
	solo_b.position = Vector3(200, 0, 200)
	solo_b.rebuild()
	var solo_b_n := solo_b.snap_transforms.size()
	await process_frame

	# EQUAL RANKS IGNORE EACH OTHER — every scene built before junctions existed is untouched
	var same_a := _styled(plan, st, 3.0, 9)
	var same_b := _junc_tower(st, Vector3(6.0, 0, 5.0), 0)
	same_a.rebuild()
	await process_frame
	_check(same_a.snap_transforms.size() == solo_b_n,
			"junction: equal ranks cut each other (%d vs %d)"
					% [same_a.snap_transforms.size(), solo_b_n])

	# a STRICTLY higher rank wins
	var block := _styled(plan, st, 3.0, 9)
	var tower := _junc_tower(st, Vector3(6.0, 0, 5.0), 5)
	block.rebuild()
	await process_frame
	_check(block.snap_transforms.size() < solo_b_n, "junction: the block gave up nothing")
	var inside := 0
	for t in block.snap_transforms:
		var q := block.to_global(t.origin)
		if Vector2(q.x - 6.0, q.z - 5.0).length() < 1.35 and q.y < 5.0:
			inside += 1
	_check(inside == 0, "junction: %d block stones still stand inside the tower" % inside)
	# THE WINNER IS NOT DISTURBED. Once seam rules existed this stopped being "identical" and became
	# "a superset": the winner still has every stone it had standing alone, in the same place and the
	# same colour, and whatever it has ON TOP of those is dressing it added because of the junction —
	# never a stone that moved. Weakening the equality to containment is the whole difference between
	# "a junction may not disturb the winner" and "a junction may not add anything", and only the
	# first was ever the promise.
	var won := _bricks(tower)
	var lost := 0
	for k in solo_sig:
		if not won.has(k):
			lost += 1
	_check(lost == 0,
			"junction: THE WINNER MOVED — %d of its %d stones are not where they were standing alone"
			% [lost, solo_sig.size()])
	_check(won.size() - solo_sig.size() == int(tower.stats.get("tees", 0)),
			"junction: the winner gained %d pieces but reports %d tee quoins"
			% [won.size() - solo_sig.size(), int(tower.stats.get("tees", 0))])
	_done("junction")


func _junc_tower(st: GladeStyle, at: Vector3, rank: int) -> GladeWall:
	var w := GladeWall.new()
	w.style = st
	w.rng_seed = 3
	w.wall_height = 5.0
	w.junction_rank = rank
	w.generate_collision = false
	w.position = at
	root.add_child(w)
	w.make_cylinder(1.6, 20)
	w.rebuild()
	return w


## INTERIOR FLOORS. Off by default; on, a storeyed building stops being a hollow shell.
func _floor_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5), Vector3.ZERO]

	var bare := _styled(plan, st, 2.4, 9)
	bare.storeys = [_floor_storey(2.6, false, st), _floor_storey(2.4, false, st)]
	bare.rebuild()
	await process_frame
	_check(int(bare.stats.get("floors", 0)) == 0, "floors: off by default should grow nothing")
	_check(_pieces_at(bare, Vector3(3.0, 2.65, 2.5)) == 0,
			"floors CONTROL: the upper storey should be a hollow shell")

	var w := _styled(plan, st, 2.4, 9)
	w.storeys = [_floor_storey(2.6, true, st), _floor_storey(2.4, true, st)]
	w.rebuild()
	await process_frame
	_check(int(w.stats.get("floors", 0)) > 10,
			"floors: only %d boards laid" % int(w.stats.get("floors", 0)))
	_check(_pieces_at(w, Vector3(3.0, 2.65, 2.5)) > 0, "floors: no floor at the first storey")
	_check(_pieces_at(w, Vector3(3.0, 1.5, 2.5)) == 0, "floors: the room itself got filled in")
	_check(_pieces_at(w, Vector3(-0.6, 0.05, 2.5)) == 0, "floors: the slab spills outside the wall")

	# a round tower's boards are cut to the CIRCLE, not to a box
	var t := GladeWall.new()
	t.style = st
	t.rng_seed = 3
	t.generate_collision = false
	t.storeys = [_floor_storey(3.0, true, st)]
	root.add_child(t)
	t.make_cylinder(2.0, 20)
	t.rebuild()
	await process_frame
	var lens: Array[float] = []
	for tr in t.snap_transforms:
		if absf(tr.origin.y - 0.045) < 0.03:
			lens.append(tr.basis.get_scale().x)
	lens.sort()
	_check(lens.size() >= 5, "floors: a round tower got %d boards" % lens.size())
	_check(lens.size() >= 5 and lens[lens.size() - 1] > lens[0] * 1.35,
			"floors: the boards are not cut to the circle")
	_done("floors")


func _fp_square(cx: float, cz: float, hx: float, hz: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx - hx, cz - hz), Vector2(cx + hx, cz - hz),
			Vector2(cx + hx, cz + hz), Vector2(cx - hx, cz + hz)])


## THE MASSING LAYER. A volume could only ever be asked about a POINT, which is enough to delete a
## brick and nothing else — so every junction was a hand-rolled way of removing pieces and none
## could add one. `faces()` is what a seam is computed FROM, so it is pinned first.
func _faces_suite() -> void:
	var pr := GladeVolume.prism(_fp_square(0, 0, 1, 1), 0.0, 2.0)
	var fs := pr.faces()
	_check(fs.size() == 6, "faces: a box footprint gave %d faces, expected 6" % fs.size())
	var out_bad := 0
	var in_bad := 0
	for f in fs:
		var c := Vector3.ZERO
		for p in f.polygon:
			c += p
		c /= f.polygon.size()
		var n: Vector3 = f.normal
		if pr.contains(c + n * 0.05):
			out_bad += 1                       # stepping OUT along the normal must leave the solid
		if not pr.contains(c - n * 0.05):
			in_bad += 1                        # stepping IN must stay inside it
	_check(out_bad == 0, "faces: %d normals point INTO the solid" % out_bad)
	_check(in_bad == 0, "faces: %d faces do not sit on the solid's surface" % in_bad)

	# THE WINDING CONTRACT. A face's polygon winds counter-clockwise about its outward normal —
	# that is the right-hand rule Newell's method uses to find the normal in the first place. Godot
	# renders the opposite convention: front faces wind CLOCKWISE seen from outside. Anything that
	# draws these has to reverse them, and forgetting culls every outward face and leaves you
	# looking at the inside of the building with the ground visible through its walls.
	var wound := 0
	for f in fs:
		var poly: PackedVector3Array = f.polygon
		var n: Vector3 = f.normal
		var rh := (poly[1] - poly[0]).cross(poly[2] - poly[0])
		if rh.dot(n) <= 0.0:
			wound += 1
	_check(wound == 0,
			"faces: %d polygons do not wind counter-clockwise about their own normal" % wound)

	# a wedge is the shape a valley is found on, so its faces have to be right too
	var w := GladeVolume.wedge(Vector3(0, 3, 0), Basis.IDENTITY, Vector3(3, 0.02, 2), 1.6)
	var wf := w.faces()
	_check(wf.size() >= 5, "faces: a wedge gave %d faces, expected at least 5" % wf.size())
	var up := 0
	for f in wf:
		if (f.normal as Vector3).y > 0.3:
			up += 1
	_check(up >= 2, "faces: a gable should present two upward slopes, found %d" % up)
	_done("faces")


## WHERE TWO SOLIDS MEET — a line or a surface, and both are real junctions. This is the
## computation every junction fix so far has been a hand-rolled special case of.
func _seam_suite() -> void:
	# an L of two overlapping boxes: it has a reflex corner, so it must produce a CONCAVE seam
	var a := GladeVolume.prism(_fp_square(-1, 0, 1, 1), 0.0, 2.0)
	a.owner_id = 1
	var b := GladeVolume.prism(_fp_square(0, 1, 1, 1), 0.0, 2.0)
	b.owner_id = 2
	var seams: Array = GladeSeam.between(a, [b])
	var conc := 0
	var conv := 0
	for s: GladeSeam in seams:
		if s.kind == GladeSeam.Kind.SEGMENT:
			if s.turn == GladeSeam.Turn.CONCAVE:
				conc += 1
			else:
				conv += 1
	_check(seams.size() > 0, "seam: an overlapping L produced none")
	_check(conc >= 1, "seam: no CONCAVE seam at the L's reflex corner")
	_check(conv >= 1, "seam: no CONVEX seam anywhere on the L")

	# THE CONTROL. Without this the whole suite passes just as well on code that reports seams
	# between every pair of solids in the scene.
	var far := GladeVolume.prism(_fp_square(50, 50, 1, 1), 0.0, 2.0)
	far.owner_id = 3
	_check((GladeSeam.between(a, [far]) as Array).is_empty(),
			"seam CONTROL: detached solids should share nothing")

	# a party wall: two prisms flush along one face overlap in an AREA, not a line
	var l := GladeVolume.prism(_fp_square(0, 0, 1, 1), 0.0, 3.0)
	l.owner_id = 4
	var r := GladeVolume.prism(_fp_square(2, 0, 1, 1), 0.0, 3.0)
	r.owner_id = 5
	var biggest := 0.0
	var patches := 0
	for s: GladeSeam in GladeSeam.between(l, r_arr(r)):
		if s.kind == GladeSeam.Kind.PATCH:
			patches += 1
			biggest = maxf(biggest, s.measure())
	_check(patches >= 1, "seam: two flush walls gave no PATCH")
	_check(absf(biggest - 6.0) < 0.3,
			"seam: the party wall patch is %.2f m2, expected the shared face's 6.0" % biggest)
	_done("seam")


func r_arr(v: GladeVolume) -> Array:
	return [v]


## A BURIED REGION IS A REGION, NOT AN ABSENCE. Where one building swallows another's wall, that
## wall is still there — plastered, or left rough — and answering with deletion can only ever say
## "nothing". `buried_style` is the rule for that region; this pins that it is built, that it is
## built out of the right thing, and that leaving it null changes nothing.
func _buried_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5), Vector3.ZERO]

	# alone, for the baseline
	var solo := _styled(plan, st, 3.0, 9)
	solo.position = Vector3(300, 0, 300)
	solo.rebuild()
	await process_frame
	var alone := solo.snap_transforms.size()

	# a higher-ranked tower driven into it: the block loses that stone
	var plain := _styled(plan, st, 3.0, 9)
	var t1 := _junc_tower(st, Vector3(6.0, 0, 5.0), 5)
	plain.rebuild()
	await process_frame
	var cut := plain.snap_transforms.size()
	_check(cut < alone, "buried: the block did not give up any stone (%d vs %d)" % [cut, alone])

	# now give it a buried style: the SAME region comes back, built out of that instead
	var inner: GladeStyle = st.duplicate()
	inner.palette = [Color(0.9, 0.2, 0.2)] as Array[Color]   # unmistakable, for counting
	inner.palette_weights = PackedFloat32Array([1])
	var dressed_style: GladeStyle = st.duplicate()
	dressed_style.buried_style = inner
	var dressed := _styled(plan, dressed_style, 3.0, 9)
	var t2 := _junc_tower(st, Vector3(6.0, 0, 5.0), 5)
	dressed.rebuild()
	await process_frame
	var filled := dressed.snap_transforms.size()
	_check(filled > cut,
			"buried: buried_style grew nothing (%d, same as deleting: %d)" % [filled, cut])

	# and what came back is the INNER style, not the outer one
	var reds := 0
	for c in dressed.snap_colors:
		if c.r > c.g * 1.8 and c.r > c.b * 1.8:
			reds += 1
	_check(reds > 0, "buried: none of the refilled stone uses the buried style")

	# THE ADDITIVE GUARANTEE: no buried_style means byte-identical to plain deletion.
	var again := _styled(plan, st, 3.0, 9)
	var t3 := _junc_tower(st, Vector3(6.0, 0, 5.0), 5)
	again.rebuild()
	await process_frame
	_check(_bricks(again) == _bricks(plain),
			"buried: a null buried_style changed the output")
	_done("buried")


## A VALLEY IS A PIECE, NOT AN ABSENCE — the first rule to CONSUME the massing layer instead of
## deleting with it. Two roofs crossing fold into the line rain runs down, and nothing a claim can do
## puts lead in a gutter: clearing the loser's tiles only leaves a bare mitre.
##
## THE CONTROL: two roofs that do NOT cross must produce nothing. Without it this suite passes just
## as well on code that laps a seam between every roof in the scene.
func _valley_suite() -> void:
	var far := Vector3(400, 0, 400)
	var a := _roofed_block(far + Vector3(-4.0, 0, 0), 9.0, 5.0, 3.2, 44.0, 3)
	var b := _roofed_block(far + Vector3(1.4, 0, -4.6), 4.6, 9.5, 3.2, 44.0, 8)
	var ra: GladeRoof = a.get_child(0)
	var rb: GladeRoof = b.get_child(0)
	await process_frame
	ra.rebuild()
	rb.rebuild()
	await process_frame

	var laid := int(ra.stats.get("valleys", 0)) + int(rb.stats.get("valleys", 0))
	_check(laid > 0, "valley: two crossing roofs laid nothing in the fold")
	# exactly one of the two dresses it, or every valley is two valleys fighting over the same 5 cm
	_check(int(ra.stats.get("valleys", 0)) == 0 or int(rb.stats.get("valleys", 0)) == 0,
			"valley: BOTH roofs dressed the same folds (%s and %s pieces)"
			% [str(ra.stats.get("valleys")), str(rb.stats.get("valleys"))])

	# the tiles underneath are untouched: take one roof away and what is left must still be there,
	# tile for tile, with only the valley pieces missing
	var with_b := _tiles(ra)
	b.position += Vector3(0, 0, 300)
	ra.rebuild()
	rb.rebuild()
	await process_frame
	var alone := _tiles(ra)
	_check(int(ra.stats.get("valleys", 0)) == 0 and int(rb.stats.get("valleys", 0)) == 0,
			"valley CONTROL: two roofs 300 m apart still laid %s + %s pieces"
			% [str(ra.stats.get("valleys")), str(rb.stats.get("valleys"))])
	var moved := 0
	for k in alone:
		if not with_b.has(k):
			moved += 1
	_check(moved == 0,
			"valley: %d of the %d tiles this roof lays alone moved when a roof crossed it"
			% [moved, alone.size()])

	# ...and the switch really is a switch
	b.position -= Vector3(0, 0, 300)
	ra.valley_tiles = false
	rb.valley_tiles = false
	ra.rebuild()
	rb.rebuild()
	await process_frame
	_check(_tiles(ra) == alone,
			"valley: valley_tiles off is not the roof standing alone (%d vs %d pieces)"
			% [_tiles(ra).size(), alone.size()])

	a.free()
	b.free()
	_done("valley")


## A WALL TEE: another building's wall dying into this one. Deletion stops the loser's courses at a
## raw sawn end, a different amount short on every course, and cannot put the closer stone there.
##
## THE CONTROL: equal ranks. They do not junction, so nothing has given way, so there is no joint to
## quoin — and every scene built before this rule existed keeps exactly the stones it had.
func _tee_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5), Vector3.ZERO]
	var far := Vector3(500, 0, 500)

	var solo := _junc_tower(st, far + Vector3(400, 0, 0), 5)
	var solo_sig := _bricks(solo)

	var block := _styled(plan, st, 3.0, 9)
	block.position = far
	var tower := _junc_tower(st, far + Vector3(6.0, 0, 5.0), 5)
	block.rebuild()
	await process_frame

	_check(int(tower.stats.get("tees", 0)) > 0,
			"tee: a tower driven into a block quoined nothing")
	_check(int(block.stats.get("tees", 0)) == 0,
			"tee: the LOSER laid %s quoins — dressing a tee is the winner's job"
			% str(block.stats.get("tees")))
	# what it added is the joint, not a second wall: every extra piece stands on the seam
	var won := _bricks(tower)
	_check(won.size() - solo_sig.size() == int(tower.stats.get("tees", 0)),
			"tee: the tower gained %d pieces but reports %s quoins"
			% [won.size() - solo_sig.size(), str(tower.stats.get("tees"))])
	var lost := 0
	for k in solo_sig:
		if not won.has(k):
			lost += 1
	_check(lost == 0, "tee: quoining a joint moved %d of the tower's own stones" % lost)

	# EQUAL RANKS: no winner, no tee
	var flat := _styled(plan, st, 3.0, 9)
	flat.position = far + Vector3(0, 0, 200)
	var peer := _junc_tower(st, far + Vector3(6.0, 0, 205.0), 0)
	flat.rebuild()
	await process_frame
	_check(int(peer.stats.get("tees", 0)) == 0 and int(flat.stats.get("tees", 0)) == 0,
			"tee CONTROL: equal ranks quoined each other (%s and %s)"
			% [str(peer.stats.get("tees")), str(flat.stats.get("tees"))])

	# and the switch
	tower.tee_quoins = false
	tower.rebuild()
	await process_frame
	_check(_bricks(tower) == solo_sig, "tee: tee_quoins off is not the tower standing alone")

	solo.free(); block.free(); tower.free(); flat.free(); peer.free()
	_done("tee")


## SOFT SNAP. A dragged face lands on the style's own module, so a wall is usually a whole number of
## pieces and the residue left for the seam block to absorb is small.
##
## THE CONTROL: a wall with no style keeps the old 0.25 m grid, and the two answers must differ —
## otherwise this passes on code that never read a style at all.
func _snap_suite() -> void:
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var timber: GladeStyle = load("res://addons/gladekit/styles/alsace_timber.tres")
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5), Vector3.ZERO]

	var bare := _wall(plan, 2.6)
	bare.position = Vector3(600, 0, 600)
	bare.plan_mode = GladeWall.PlanMode.BOX
	await process_frame
	_check(absf(bare.snap_step() - GladeWall.BOX_SNAP) < 0.0001,
			"snap: a wall with no style should keep the %.2f grid, got %.3f"
			% [GladeWall.BOX_SNAP, bare.snap_step()])

	var w := _styled(plan, timber, 2.6, 5)
	w.position = Vector3(600, 0, 640)
	w.plan_mode = GladeWall.PlanMode.BOX
	await process_frame
	var bay: float = timber.bay_width
	_check(absf(w.snap_step() - bay) < 0.0001,
			"snap: a timber wall's step is %.3f, wanted its %.2f bay" % [w.snap_step(), bay])
	_check(absf(bay - GladeWall.BOX_SNAP) > 0.02,
			"snap CONTROL: the bay and the old grid are the same number, so this proves nothing")

	# drag one face to an untidy place: the SPAN comes out a whole number of bays
	w.push_face(2, Vector3(3.0, 0, 7.13))
	await process_frame
	var d: float = w.box_plan().d
	_check(absf(d - snappedf(d, bay)) < 0.001,
			"snap: a dragged timber face spans %.3f m, which is %.2f bays" % [d, d / bay])
	_check(absf(d - snappedf(d, GladeWall.BOX_SNAP)) > 0.001 or absf(bay - 0.25) < 0.001,
			"snap CONTROL: %.3f is on the old grid too, so the module was not what decided it" % d)

	var m := _styled(plan, stone, 2.6, 5)
	m.position = Vector3(600, 0, 680)
	await process_frame
	var module: float = (stone.brick_min_width + stone.brick_max_width) * 0.5 + stone.gap
	_check(absf(m.snap_step() - module) < 0.0001,
			"snap: a masonry wall's step is %.3f, wanted its %.3f brick" % [m.snap_step(), module])

	bare.free(); w.free(); m.free()
	_done("snap")


## ONE NUMBER IS THE WHOLE PRIMITIVE SET. `plan_sides` says how many sides the footprint has, and
## everything downstream reads it: the prism, the roof above it (a cone lays exactly that many
## slopes, so 3 is a three-sided pyramid and 20 reads round), and the masonry at the corners.
##
## THE CONTROL is the square. Four equidistant corners are a square tower and a square HOUSE, and
## nothing measurable tells them apart — so a box-plan square must still get a gable. Without the
## intent rule in GladeRoof._plan() every box house in every scene grows a pyramid, and this is the
## assertion that catches it.
func _shapes_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var far := Vector3(700, 0, 700)
	var built: Array[GladeWall] = []

	var i := 0
	for sides: int in [3, 4, 5, 6, 8, 12, 20]:
		var w := GladeWall.new()
		w.style = st
		w.rng_seed = 4
		w.wall_height = 3.0
		w.generate_collision = false
		root.add_child(w)
		w.position = far + Vector3(i * 40, 0, 0)
		w.make_cylinder(2.0, sides)
		var r := GladeRoof.new()
		r.pitch_degrees = 50.0
		r.eave_brackets = false
		w.add_child(r)
		await process_frame
		await process_frame
		built.append(w)
		i += 1

		_check(w.curve.point_count == sides + 1,
				"shapes(%d): the footprint has %d points, wanted %d"
				% [sides, w.curve.point_count, sides + 1])
		_check(w.plan_sides == sides,
				"shapes(%d): plan_sides reads back %d" % [sides, w.plan_sides])
		_check(absf(w.plan_radius - 2.0) < 0.001,
				"shapes(%d): plan_radius reads back %.3f, wanted 2.000" % [sides, w.plan_radius])
		# a regular polygon's area, which is what the footprint has to be
		var want_area: float = 0.5 * sides * 4.0 * sin(TAU / sides)
		_check(absf(_plan_area(w) - want_area) < want_area * 0.02,
				"shapes(%d): footprint is %.2f m2, wanted %.2f"
				% [sides, _plan_area(w), want_area])
		# and the roof followed, with no roof code involved: N sides, N slopes
		_check(str(r.stats.get("shape", "")) == "cone",
				"shapes(%d): an AUTO roof on a declared polygon came out as a gable" % sides)
		_check(int(r.stats.get("segments", 0)) == sides,
				"shapes(%d): the roof laid %s slopes" % [sides, str(r.stats.get("segments"))])

	# corners fall out of the turn angle, not out of a special case: a hexagon turns 60 degrees at
	# every vertex and gets quoined; a 20-gon turns 18 and stays smooth
	_check(int(built[3].stats.get("quoins", 0)) > 0,
			"shapes: a hexagonal tower grew no quoins at its corners")
	_check(int(built[6].stats.get("quoins", 0)) == 0,
			"shapes: a 20-sided tower quoined %s corners — it has none sharp enough"
			% str(built[6].stats.get("quoins")))

	# THE CONTROL -- a BOX-plan square is a house, and a house gets a gable
	var box := _styled([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4),
			Vector3.ZERO], st, 3.0, 4)
	box.position = far + Vector3(0, 0, 60)
	box.plan_mode = GladeWall.PlanMode.BOX
	var box_roof := GladeRoof.new()
	box_roof.pitch_degrees = 50.0
	box_roof.eave_brackets = false
	box.add_child(box_roof)
	await process_frame
	await process_frame
	_check(box.cylinder_plan().ok,
			"shapes CONTROL: a square no longer reads as a polygon, so this proves nothing")
	_check(str(box_roof.stats.get("shape", "")) != "cone",
			"shapes CONTROL: A SQUARE HOUSE GREW A PYRAMID — intent must beat the geometry")

	# THE OTHER CONTROL -- the curve is the authority and the property is only a view on it. It is
	# never saved, so a stored number can never reshape a footprint somebody edited by hand.
	var view := built[3]
	view.set_cylinder_plan(view.cylinder_plan().centre, 2.0, 5)
	_check(view.plan_sides == 5,
			"shapes: plan_sides answered %d after the CURVE was set to 5 sides" % view.plan_sides)
	var packed := PackedScene.new()
	packed.pack(view)
	var stored: Array[String] = []
	var state := packed.get_state()
	for pi in state.get_node_property_count(0):
		stored.append(state.get_node_property_name(0, pi))
	_check(not stored.has("plan_sides") and not stored.has("plan_radius"),
			"shapes: plan_sides/plan_radius were SAVED into the scene — a second representation")
	var reloaded := packed.instantiate() as GladeWall
	root.add_child(reloaded)
	reloaded.position = far + Vector3(0, 0, 120)
	await process_frame
	_check(reloaded.plan_sides == 5 and reloaded.curve.point_count == 6,
			"shapes: a packed and reloaded polygon came back as %d sides / %d points"
			% [reloaded.plan_sides, reloaded.curve.point_count])

	for w in built:
		w.free()
	box.free()
	reloaded.free()
	_done("shapes")


## THE BELL-CAST. A slope that runs dead straight into its gutter is the tell of a roof nobody
## built; `eave_flare` eases the pitch over the last stretch so the eave sails outward.
##
## What has to hold is that ONE function does it. A roof has two doors into slope geometry — the
## tiler and `_slope_pt`, which is where dormers, chimneys and flashing ask where the surface is —
## and flaring one but not the other is invisible until a dormer sinks through its own roof.
func _flare_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _styled([Vector3.ZERO, Vector3(8, 0, 0), Vector3(8, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], st, 3.0, 6)
	w.position = Vector3(800, 0, 800)
	w.generate_collision = false
	var r := GladeRoof.new()
	r.pitch_degrees = 50.0
	r.overhang = 0.5
	r.sag = 0.0                                    # one variable at a time
	r.eave_brackets = false
	w.add_child(r)
	await process_frame
	await process_frame

	var flat := _tiles(r)
	var flat_reach := _eave_reach(r)
	# The cut is taken ONCE, off the flat roof, and reused. Taking it per-run would move with the
	# roof it is measuring: a flared row lies shallower, so its tiles' lift tilts and the lowest
	# tile's height shifts by a centimetre — enough to slide the boundary past five tiles and
	# report a bend as a scale.
	var cut_y := _mid_height(r)
	var flat_high := _high_tiles(r, cut_y)
	var flat_out := _claim_overshoot(r)
	var ctx0: Dictionary = r.call("_plan", w.roof_host())
	var foot0: Vector3 = r.call("_slope_pt", ctx0, 1.0, 0.0, 0.0)

	r.eave_flare = 0.35
	r.flare_span = 0.25
	r.rebuild()
	await process_frame

	# 1 -- the eave sails out
	_check(_eave_reach(r) > flat_reach + 0.25,
			"flare: the eave reaches %.2f m, barely past the %.2f m it had flat"
			% [_eave_reach(r), flat_reach])
	# 2 -- and only the eave: everything above the flare is where it was, stone for stone
	var moved := 0
	var now_high := _high_tiles(r, cut_y)
	for k in flat_high:
		if not now_high.has(k):
			moved += 1
	_check(moved == 0,
			"flare: %d of the %d tiles above the flare moved — this is a bend, not a scale"
			% [moved, flat_high.size()])
	# 3 -- THE ONE THAT MATTERS: `_slope_pt` bends by exactly as much, so anything that places
	# itself on the slope lands ON the tiles instead of through them
	var foot1: Vector3 = r.call("_slope_pt", ctx0, 1.0, 0.0, 0.0)
	_check(absf(foot1.distance_to(foot0) - 0.35) < 0.001,
			"flare: the tiler flares but _slope_pt moved %.3f m — the two doors disagree"
			% foot1.distance_to(foot0))
	_check(absf(foot1.y - foot0.y) < 0.0001,
			"flare: the eave line CHANGED HEIGHT by %.3f m — a bell-cast bends, it does not shear"
			% absf(foot1.y - foot0.y))
	# 4 -- the claim grew with the roof. Measured against the FLAT roof's own count, not against
	# zero: a roof has always had a few pieces outside its wedge (the ridge caps sit above the
	# apex, and every tile is lifted along its normal), and the thing that matters is that a flare
	# does not add to them.
	_check(_claim_overshoot(r) <= flat_out + 0.001,
			"flare: the outermost tile stands %.3f m outside the claim's footprint, against %.3f m flat — the wedge did not grow with the flare"
			% [_claim_overshoot(r), flat_out])

	# THE CONTROL -- off is off, to the last decimal
	r.eave_flare = 0.0
	r.rebuild()
	await process_frame
	_check(_tiles(r) == flat, "flare: eave_flare 0 is not the roof this was before the flare existed")

	w.free()
	_done("flare")


## The footprint's area, straight off the curve.
func _plan_area(w: GladeWall) -> float:
	var pts := PackedVector2Array()
	var n := w.curve.point_count - 1                # a closed loop repeats its first point
	for i in n:
		var p := w.curve.get_point_position(i)
		pts.append(Vector2(p.x, p.z))
	var a := 0.0
	for i in pts.size():
		var q := pts[i]
		var s := pts[(i + 1) % pts.size()]
		a += q.x * s.y - s.x * q.y
	return absf(a) * 0.5


## How far the lowest tiles reach from the ridge line, horizontally — the number a flare moves.
func _eave_reach(r: GladeRoof) -> float:
	var lo := INF
	for t in r.snap_transforms:
		lo = minf(lo, t.origin.y)
	var reach := 0.0
	for t in r.snap_transforms:
		if t.origin.y < lo + 0.2:
			reach = maxf(reach, absf(t.origin.z))
	return reach


## Halfway up whatever this roof currently occupies.
func _mid_height(r: GladeRoof) -> float:
	var hi := -INF
	var lo := INF
	for t in r.snap_transforms:
		hi = maxf(hi, t.origin.y)
		lo = minf(lo, t.origin.y)
	return lo + (hi - lo) * 0.5


## Every tile above a fixed height, as a signature — above the flare these must not move.
func _high_tiles(r: GladeRoof, cut: float) -> Dictionary:
	var out := {}
	for t in r.snap_transforms:
		if t.origin.y > cut:
			out["%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z]] = true
	return out


## How far the furthest tile sticks out past the claim's FOOTPRINT, horizontally. Height is left
## alone deliberately: a ridge cap sits five centimetres above the wedge's apex and always has, so
## a y-aware version would measure that instead of the thing a flare can break.
func _claim_overshoot(r: GladeRoof) -> float:
	var vols := r.junction_volumes()
	if vols.is_empty():
		return 0.0
	var box: AABB = (vols[0] as GladeVolume).aabb()
	var worst := 0.0
	for t in r.snap_transforms:
		var p := r.to_global(t.origin)
		worst = maxf(worst, maxf(box.position.x - p.x, p.x - box.end.x))
		worst = maxf(worst, maxf(box.position.z - p.z, p.z - box.end.z))
	return worst


## THE CLAY AS ONE COHERENT BLOCK. A mud wall has no pieces, so this mode emits a surface instead of
## instancing — and the assertions have to follow it there. A test that counted bricks on an adobe
## wall would read zero and "pass" while proving nothing at all, which is the trap this suite exists
## to avoid.
func _adobe_suite() -> void:
	var far := Vector3(900, 0, 900)
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 4), Vector3(0, 0, 4), Vector3.ZERO]
	var clay: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres").duplicate()
	clay.wall_mode = GladeStyle.WallMode.ADOBE

	var w := _styled(plan, clay, 3.0, 5)
	w.position = far
	w.generate_collision = false
	_opening(w, 2.0, 0.0, 1.3, 2.1)                # a door: sill on the ground
	w.rebuild()
	await process_frame

	var surf := _adobe_mesh(w)
	_check(surf != null, "adobe: no surface — the mode grew nothing at all")
	_check(int(w.stats.get("adobe_quads", 0)) > 0,
			"adobe: reports %s quads" % str(w.stats.get("adobe_quads")))
	# IT DOES NOT INSTANCE. Half the point of the mode, and the reason every piece-counting
	# assertion has to stay away from it.
	_check(w.snap_transforms.is_empty(),
			"adobe: placed %d instances — a mud wall has no pieces" % w.snap_transforms.size())

	if surf != null:
		# RAW, NOT EXPANDED — this suite pairs each vertex with its own NORMAL by index, and
		# `_tri_verts` walks the index buffer, so the two arrays would be different lengths and the
		# pairing would be nonsense before it ran off the end.
		var verts: PackedVector3Array = surf.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(verts.size() > 100, "adobe: only %d vertices in the surface" % verts.size())
		# THE HOLE IS REALLY CUT. The door's middle is empty clay: nothing may be near it, and the
		# nearest thing to it should be the reveal around its edge.
		var hole := w.curve.sample_baked(2.0) + Vector3.UP * 1.05
		var through := 0
		for v in verts:
			if v.distance_to(hole) < 0.45:
				through += 1
		_check(through == 0,
				"adobe: %d vertices stand inside the doorway — the opening was not cut" % through)

		# NORMALS POINT OUT, and the face is FRONT-facing that way. Getting this wrong is invisible
		# on a two-sided shell — you always see something, it is just the inside of the far face lit
		# backwards — which is exactly why it needs pinning. Same trap the `faces` suite pins for
		# GladeVolume: Godot's front face is CLOCKWISE about the outward normal, so a loop wound
		# counter-clockwise about it renders inside-out.
		var arrays := surf.surface_get_arrays(0)
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		# SurfaceTool without index() commits an UNINDEXED surface: ARRAY_INDEX is null and the
		# vertices are already in triangle order. Build the identity so one loop reads both.
		var idx := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		else:
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var centre := Vector3(3.0, 0.0, 2.0)   # the middle of this 6 x 4 footprint
		var outward := 0
		var inward := 0
		for i in verts.size():
			var away := Vector3(verts[i].x - centre.x, 0.0, verts[i].z - centre.z)
			if away.length() < 1.4:            # skip the doorway reveals, which face sideways
				continue
			if absf(norms[i].y) > 0.7:
				continue                       # and the top and bottom caps
			if norms[i].dot(away.normalized()) > 0.3:
				outward += 1
			elif norms[i].dot(away.normalized()) < -0.3:
				inward += 1
		_check(outward > 0 and inward > 0,
				"adobe: the shell is one-sided (%d out, %d in)" % [outward, inward])
		# and the winding agrees with the normal it was given
		var wound := 0
		var backwards := 0
		for t in range(0, idx.size() - 2, 3):
			var p0 := verts[idx[t]]
			var geo := (verts[idx[t + 1]] - p0).cross(verts[idx[t + 2]] - p0)
			if geo.length() < 0.000001:
				continue
			if geo.normalized().dot(norms[idx[t]]) < 0.0:
				wound += 1                     # clockwise about the normal = Godot's front face
			else:
				backwards += 1
		_check(backwards == 0,
				"adobe: %d of %d triangles are wound INSIDE-OUT — Godot's front face is clockwise about the outward normal"
				% [backwards, wound + backwards])

		# NO BRICK PATTERN. Colouring per CELL — one palette pick each, the way `_emit_brick` does —
		# paints brickwork onto a continuous surface: every cell is a flat rectangle of its own
		# shade and the tessellation is the first thing you see. The tell is that two cells meeting
		# at a corner disagree about that corner's colour. Sampling at the corners instead makes
		# them agree by construction, so this is the assertion that keeps clay from looking laid.
		var cols_arr: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var seen := {}
		var clashes := 0
		for i in verts.size():
			var key := "%.3f,%.3f,%.3f" % [verts[i].x, verts[i].y, verts[i].z]
			if seen.has(key):
				var other: Color = seen[key]
				if absf(other.r - cols_arr[i].r) + absf(other.g - cols_arr[i].g) 						+ absf(other.b - cols_arr[i].b) > 0.02:
					clashes += 1
			else:
				seen[key] = cols_arr[i]
		_check(clashes == 0,
				"adobe: %d shared corners disagree about their colour — the surface is being shaded per CELL, which draws bricks on it"
				% clashes)

	# CONTROL — the same wall in masonry is pieces and no surface. Without the branch in
	# _fill_run() this fails, and it is what proves the two modes are actually different code.
	var stone: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var m := _styled(plan, stone, 3.0, 5)
	m.position = far + Vector3(0, 0, 40)
	m.generate_collision = false
	m.rebuild()
	await process_frame
	_check(_adobe_mesh(m) == null and not m.snap_transforms.is_empty(),
			"adobe CONTROL: a MASONRY wall grew a clay surface, or grew no bricks")

	w.free(); m.free()
	_done("adobe")


## WHAT THE ZOOM FOUND. Every one of these was invisible at the framing the reference plate is drawn
## at and glaring from two metres, which is the whole reason this suite exists as well as `adobe`.
func _clay_suite() -> void:
	var far := Vector3(1600, 0, 1600)
	var clay: GladeStyle = load("res://addons/gladekit/styles/adobe_clay.tres")

	# 1. A SMOOTH PLAN SHADES SMOOTH. A facet normal per quad made an 18-sided granary read as
	#    eighteen flat panels and a dome read as a barrel. Differencing the surface at each corner
	#    instead means the normal follows the plan's curvature — so on a round tower a vertex normal
	#    must LEAN OFF its own quad, and vertices in the same place must still agree about it.
	var tower := GladeWall.new()
	tower.style = clay
	tower.rng_seed = 3
	tower.wall_height = 3.0
	tower.generate_collision = false
	root.add_child(tower)
	tower.position = far
	tower.make_cylinder(3.0, 20)
	await process_frame
	await process_frame
	var mesh := _adobe_mesh(tower)
	_check(mesh != null, "clay: the tower grew no surface")
	if mesh:
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		# EITHER WAY. `SurfaceTool` only builds an index buffer if you call `index()`, which the kit
		# now does (`GladePresent.commit`) and did not before — so this reads both shapes rather than
		# assuming one. Welding cannot change what is being measured here: `index()` merges only
		# vertices identical in EVERY attribute, so a crease with two normals stays two vertices.
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			idx.resize(vs.size())
			for i in vs.size():
				idx[i] = i
		var lean := 0.0
		for t in range(0, idx.size(), 3):
			var geo := (vs[idx[t + 1]] - vs[idx[t]]).cross(vs[idx[t + 2]] - vs[idx[t]])
			if geo.length() < 0.0000001:
				continue
			geo = geo.normalized()
			for k in 3:
				lean = maxf(lean, rad_to_deg(acos(clampf(absf(geo.dot(ns[idx[t + k]])), 0.0, 1.0))))
		# a 20-gon turns 18 degrees a facet, so a smoothed corner leans about 9 off its own quad.
		# CONTROL, in the same number: a per-face normal is 0 here, and this fails.
		_check(lean > 3.0,
				"clay: the steepest vertex normal leans only %.1f deg off its quad — the surface is FLAT-shaded, so a round tower will read as facets" % lean)
		# ...and they must agree with each other where they meet. ONLY THE WALL FACES: the cap at the
		# top of the wall and the one at the bottom are genuine creases against it, share their
		# corners with it, and are supposed to disagree — a reveal is not a smoothing failure.
		var seen := {}
		var split := 0
		for i in vs.size():
			if absf(ns[i].y) > 0.5:
				continue
			var key := "%.3f,%.3f,%.3f" % [vs[i].x, vs[i].y, vs[i].z]
			if seen.has(key):
				if (seen[key] as Vector3).dot(ns[i]) < 0.999:
					split += 1
			else:
				seen[key] = ns[i]
		_check(split == 0,
				"clay: %d shared corners disagree about their normal — the smoothing is per CELL and the facets will still show" % split)

	# 2. HOW FINELY IT IS CUT UP MUST NOT CHANGE HOW IT LOOKS. The colour and the bulge are fields
	#    read in METRES, so `adobe_cell` may only buy smoothness. Without the Nyquist clamp on the
	#    noise octaves this is exactly what breaks: the field carries detail the coarse grid cannot
	#    sample and the wall aliases into strata.
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 4), Vector3(0, 0, 4), Vector3.ZERO]
	var coarse: GladeStyle = clay.duplicate()
	coarse.adobe_cell = 0.45
	var fine: GladeStyle = clay.duplicate()
	fine.adobe_cell = 0.18
	var wc := _styled(plan, coarse, 3.0, 4); wc.position = far + Vector3(0, 0, 40)
	var wf := _styled(plan, fine, 3.0, 4); wf.position = far + Vector3(0, 0, 80)
	await process_frame
	await process_frame
	var mc := _mean_color(_adobe_mesh(wc))
	var mf := _mean_color(_adobe_mesh(wf))
	var drift: float = absf(mc.r - mf.r) + absf(mc.g - mf.g) + absf(mc.b - mf.b)
	_check(drift < 0.05,
			"clay: the mean colour moved %.3f between a 0.45 m grid and a 0.18 m one — the shading is keyed to CELLS, not to the wall" % drift)
	_check(_adobe_verts(wf) > _adobe_verts(wc) * 2,
			"clay CONTROL: the fine grid grew %d vertices against %d — adobe_cell did nothing at all"
					% [_adobe_verts(wf), _adobe_verts(wc)])

	# 3. A COB CORNER IS A LUMP. `adobe_round` pulls the clay in at a fold and nowhere else — which
	#    is the whole assertion: the corner moves and the middle of the wall does not.
	var sharp: GladeStyle = clay.duplicate()
	sharp.adobe_round = 0.0
	var round_st: GladeStyle = clay.duplicate()
	round_st.adobe_round = 0.18
	var ws := _styled(plan, sharp, 3.0, 4); ws.position = far + Vector3(0, 0, 120)
	var wr := _styled(plan, round_st, 3.0, 4); wr.position = far + Vector3(0, 0, 160)
	await process_frame
	await process_frame
	var mid := Vector3(2.5, 0, 0)
	var cut: float = _widest(ws) - _widest(wr)
	_check(cut > 0.05,
			"clay: rounding pulled the fold in by only %.3f m — adobe_round is not reaching the corner" % cut)
	_check(absf(_reach_near(ws, mid) - _reach_near(wr, mid)) < 0.02,
			"clay CONTROL: the middle of the wall moved too — the rounding is not local to the fold")

	tower.free(); wc.free(); wf.free(); ws.free(); wr.free()
	_done("clay")


## The average vertex colour of an adobe shell — "how the wall looks", reduced to one number.
func _mean_color(m: Mesh) -> Color:
	if m == null:
		return Color.BLACK
	var cs: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var acc := Color(0, 0, 0)
	for c in cs:
		acc += c
	return acc / maxf(float(cs.size()), 1.0)


func _adobe_verts(w: GladeWall) -> int:
	var m := _adobe_mesh(w)
	return 0 if m == null else _tri_verts(m, 0).size()


## The furthest any clay gets from the plan's centre. On a closed plan that point is on the OUTER
## skin whichever way round the curve was drawn, which is what makes this the honest measure of a
## rounded corner: the widest thing about a box is its arris, and rounding is the statement that
## the arris is not there any more.
func _widest(w: GladeWall) -> float:
	var m := _adobe_mesh(w)
	if m == null:
		return 0.0
	var vs: PackedVector3Array = _tri_verts(m, 0)
	var best := 0.0
	for v in vs:
		best = maxf(best, Vector3(v.x, 0, v.z).distance_to(Vector3(3, 0, 2)))
	return best


## The MEAN distance from the plan's centre over the vertices nearest `where` — a local measure that
## a symmetric inset cannot fake, because it moves the two skins in opposite directions and they
## cancel. Used for the control: away from a fold, nothing may move at all.
func _reach_near(w: GladeWall, where: Vector3) -> float:
	var m := _adobe_mesh(w)
	if m == null:
		return 0.0
	var vs: PackedVector3Array = _tri_verts(m, 0)
	var acc := 0.0
	var n := 0
	for v in vs:
		var flat := Vector3(v.x, 0, v.z)
		if flat.distance_to(where) < 0.45:
			acc += flat.distance_to(Vector3(3, 0, 2))
			n += 1
	return acc / maxf(float(n), 1.0)


## THE SILHOUETTE IN ELEVATION. `profile` scales the footprint with height, which is where the dome
## comes from — and it lives in `_plumb_at()`, so what has to hold is that EVERY emitter followed it,
## not just the fill.
func _profile_suite() -> void:
	var far := Vector3(1000, 0, 1000)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := GladeWall.new()
	w.style = st
	w.rng_seed = 6
	w.wall_height = 4.0
	w.generate_collision = false
	root.add_child(w)
	w.position = far
	w.make_cylinder(3.0, 16)
	await process_frame
	await process_frame
	var straight := _bricks(w)
	var base_r := _radius_between(w, 0.0, 0.6)
	var top_r := _radius_between(w, 3.2, 4.0)
	_check(absf(base_r - top_r) < 0.25,
			"profile: the tower is not straight to begin with (%.2f vs %.2f)" % [base_r, top_r])

	# CONTROL — a curve that is 1.0 everywhere must change nothing. Without it, "the dome shrank"
	# proves only that assigning a profile does something, not that it does the right thing.
	var flat := Curve.new()
	flat.add_point(Vector2(0.0, 1.0))
	flat.add_point(Vector2(1.0, 1.0))
	w.profile = flat
	w.rebuild()
	await process_frame
	_check(_bricks(w) == straight,
			"profile CONTROL: a curve of constant 1.0 moved %d stones"
			% absi(_bricks(w).size() - straight.size()))

	# ...and a dome pulls the top in while the base stays put
	var dome := Curve.new()
	dome.add_point(Vector2(0.0, 1.0))
	dome.add_point(Vector2(1.0, 0.25))
	w.profile = dome
	w.rebuild()
	await process_frame
	var base2 := _radius_between(w, 0.0, 0.6)
	var top2 := _radius_between(w, 3.2, 4.0)
	_check(absf(base2 - base_r) < 0.2,
			"profile: the BASE moved (%.2f -> %.2f) — a profile is a taper, not a scale"
			% [base_r, base2])
	_check(top2 < top_r * 0.6,
			"profile: the top is %.2f against %.2f at the base — it did not taper" % [top2, base2])

	w.free()
	_done("profile")


## A ROOF CAN BE BUILT FROM YOUR MESHES, which it could not before: it hardcoded the slab in both
## paths while walls had read `brick_meshes` since the socket existed. That asymmetry is what made
## thatch impossible.
func _roof_mesh_suite() -> void:
	var far := Vector3(1100, 0, 1100)
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 2.6, 3)
	w.position = far
	w.generate_collision = false
	var r := GladeRoof.new()
	r.pitch_degrees = 40.0
	r.eave_brackets = false
	w.add_child(r)
	await process_frame
	await process_frame
	var slab := _roof_tile_mesh(r)
	_check(slab != null, "roof_mesh: the roof grew no MultiMesh at all")

	var strand := BoxMesh.new()                    # any mesh will do; identity is what is asserted
	strand.size = Vector3(0.1, 0.02, 0.6)
	var thatch: GladeStyle = load("res://addons/gladekit/styles/alsace_slate.tres").duplicate()
	thatch.brick_meshes = [strand] as Array[Mesh]
	r.style = thatch
	r.rebuild()
	await process_frame
	_check(_roof_tile_mesh(r) == strand,
			"roof_mesh: the roof ignored the style's mesh socket and laid its own slab")

	# CONTROL — an empty socket still gets the slab it always had
	var bare: GladeStyle = load("res://addons/gladekit/styles/alsace_slate.tres")
	r.style = bare
	r.rebuild()
	await process_frame
	_check(_roof_tile_mesh(r) != strand and _roof_tile_mesh(r) != null,
			"roof_mesh CONTROL: an empty socket did not fall back to the slab")

	w.free()
	_done("roof_mesh")


## THE CLAIM IS A FUNCTION OF HEIGHT — one prism per storey, not one for the wall.
##
## A jettied wall used to claim its WIDEST footprint over its whole height, so its ground floor
## claimed half a metre of open street; `probe_buried.gd` measured 11 of whinbek's wing pieces and 7
## of its porch's standing inside no building at all, and that is what kept `buried_style` out of
## every scene. The same fault hid a second: a `profile` leans the wall face but never leaned the
## claim, so a domed granary claimed the cylinder it would have been.
func _claim_storey_suite() -> void:
	var far := Vector3(1300, 0, 1300)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 2.4, 21)
	w.style = st
	w.generate_collision = false
	w.position = far

	# COMPATIBILITY CONTROL, and it comes first on purpose: a wall with no storeys, no jetty and no
	# profile must still be ONE prism. Everything below is a measured fix; this is the promise that
	# the fix is confined to the configurations that were wrong.
	await process_frame
	var plain: Array = w.junction_volumes()
	_check(plain.size() == 1,
			"claim_storey CONTROL: a storey-less wall made %d prisms, not 1" % plain.size())

	var heights := [2.0, 2.0, 2.0]
	var jetties := [0.0, 0.3, 0.3]
	var arr: Array[GladeStorey] = []
	for i in 3:
		var s := GladeStorey.new()
		s.height = heights[i]
		s.jetty = jetties[i]
		arr.append(s)
	w.storeys = arr
	w.rebuild()
	await process_frame

	var vols: Array = w.junction_volumes()
	_check(vols.size() == 3, "claim_storey: a three-storey wall made %d prisms" % vols.size())
	if vols.size() == 3:
		# The +X face stands at x = 6 + depth/2 on the ground floor and 0.6 m further out on top.
		# A point 0.4 m past the ground face is inside the OVERHANG and outside the GROUND STOREY,
		# and telling those two apart is the whole feature.
		var out_ground: Vector3 = far + Vector3(6.4, 1.0, 2.5)
		var out_top: Vector3 = far + Vector3(6.4, 5.0, 2.5)
		_check(not (vols[0] as GladeVolume).contains(out_ground),
				"claim_storey: the ground storey still claims 0.4 m out into the street")
		_check((vols[2] as GladeVolume).contains(out_top),
				"claim_storey: the top storey does not claim the ground under its own jetty")
		# CONTROL for the assertion above — the ground band must not merely have collapsed. A point
		# just INSIDE its own face is still claimed.
		_check((vols[0] as GladeVolume).contains(far + Vector3(6.1, 1.0, 2.5)),
				"claim_storey CONTROL: the ground storey claims nothing at all — it collapsed")

	# ...and a profile leans the claim, not just the stone.
	var tower := GladeWall.new()
	tower.style = st
	tower.rng_seed = 6
	tower.wall_height = 4.0
	tower.generate_collision = false
	root.add_child(tower)
	tower.position = far + Vector3(60, 0, 0)
	tower.make_cylinder(3.0, 16)
	await process_frame
	var c0 := Vector2(tower.global_position.x, tower.global_position.z)
	var straight_top := _poly_reach((tower.junction_volumes()[0] as GladeVolume).poly, c0)

	var dome := Curve.new()
	dome.add_point(Vector2(0.0, 1.0))
	dome.add_point(Vector2(1.0, 0.25))
	tower.profile = dome
	var pair: Array[GladeStorey] = []
	for i in 2:
		var s := GladeStorey.new()
		s.height = 2.0
		pair.append(s)
	tower.storeys = pair
	tower.rebuild()
	await process_frame
	var dv: Array = tower.junction_volumes()
	_check(dv.size() == 2, "claim_storey: the domed tower made %d prisms" % dv.size())
	if dv.size() == 2:
		var base_reach := _poly_reach((dv[0] as GladeVolume).poly, c0)
		var top_reach := _poly_reach((dv[1] as GladeVolume).poly, c0)
		_check(top_reach < base_reach * 0.85,
				"claim_storey: the domed claim reaches %.2f on top against %.2f at the base — the "
				% [top_reach, base_reach] + "profile never reached the claim")
		# CONTROL — with the profile off, the two bands claim the same width again.
		tower.profile = null
		tower.rebuild()
		await process_frame
		var flat_v: Array = tower.junction_volumes()
		_check(absf(_poly_reach((flat_v[0] as GladeVolume).poly, c0)
				- _poly_reach((flat_v[1] as GladeVolume).poly, c0)) < 0.05,
				"claim_storey CONTROL: an unprofiled tower's bands claim different widths")
		_check(absf(_poly_reach((flat_v[0] as GladeVolume).poly, c0) - straight_top) < 0.05,
				"claim_storey CONTROL: adding storeys alone changed how wide the wall claims")

	tower.free()
	w.free()
	_done("claim_storey")


## A WALL OFF PLUMB. `lean` shears the whole wall one way; unlike `profile` it needs no centre to
## work about, which is why it is the first thing in the kit that can tip an OPEN wall.
func _lean_suite() -> void:
	var far := Vector3(1400, 0, 1400)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 2.4, 31)
	w.style = st
	w.generate_collision = false
	w.position = far
	await process_frame
	await process_frame

	# CONTROL FIRST. Assigning Vector2.ZERO must be indistinguishable from never touching it, or
	# every measurement below is measuring the act of setting the property.
	var upright := _bricks(w)
	var low0 := _mean_x_between(w, 0.0, 0.3)
	var high0 := _mean_x_between(w, 2.1, 2.4)
	w.lean = Vector2.ZERO
	w.rebuild()
	await process_frame
	_check(_bricks(w) == upright, "lean CONTROL: setting Vector2.ZERO moved stone")

	w.lean = Vector2(0.15, 0.0)
	w.rebuild()
	await process_frame
	var low1 := _mean_x_between(w, 0.0, 0.3)
	var high1 := _mean_x_between(w, 2.1, 2.4)
	# PROPORTIONAL TO HEIGHT is the assertion, not "it moved". A translation would move both bands
	# equally and pass a laxer test; only a shear moves the head and leaves the foot.
	_check(absf(low1 - low0) < 0.06,
			"lean: the FOOT of the wall moved %.3f m — a lean is a shear, not a slide"
			% absf(low1 - low0))
	_check(absf((high1 - high0) - 0.15 * 2.25) < 0.06,
			"lean: the head moved %.3f m where 0.15 per metre over 2.25 m wants %.3f"
			% [high1 - high0, 0.15 * 2.25])

	# THE CLAIM LEANS TOO, or a leaning wall would delete its neighbour's stone where it used to be.
	var vols: Array = w.junction_volumes()
	var reach := _poly_reach((vols[0] as GladeVolume).poly,
			Vector2(w.global_position.x, w.global_position.z))
	_check(reach > 6.0, "lean: the claim did not follow the wall over (reach %.2f)" % reach)

	# THE OPEN-WALL CONTROL — this is what proves `lean` is a new capability and not a rename of
	# `profile`. A profile is a scale about the footprint's centre, so it has nothing to work with on
	# a wall that does not close and quietly does nothing; a shear needs no centre and tips it.
	var open := _wall([Vector3.ZERO, Vector3(7, 0, 0)], 2.4, 32)
	open.style = st
	open.generate_collision = false
	open.position = far + Vector3(0, 0, 60)
	await process_frame
	await process_frame
	var open_straight := _bricks(open)
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, 0.4))
	open.profile = taper
	open.rebuild()
	await process_frame
	_check(_bricks(open) == open_straight,
			"lean CONTROL: a profile moved stone on an OPEN wall — it is documented not to")
	open.lean = Vector2(0.0, 0.2)
	open.rebuild()
	await process_frame
	_check(_bricks(open) != open_straight,
			"lean: an OPEN wall did not lean — the one case profile cannot express")

	open.free()
	w.free()
	_done("lean")


## SNAPPING — a drag lands on what is already standing there, instead of on the pixel under the mouse.
##
## `GladeAnchor` lives in `core/` precisely so this suite can execute it: the gizmo that calls it is
## the one consumer no headless test can drive, and `glade_wall.gd` records what happened last time
## geometry hid behind that line — `_tangent` was deleted as unused, every pearl in the editor broke,
## and 38 suites plus the golden dump stayed green throughout.
func _anchor_suite() -> void:
	var far := Vector3(1600, 0, 1600)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var depth: float = st.depth

	var a := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 3.0, 41)
	a.style = st
	a.generate_collision = false
	a.position = far
	# B stands off A's +X face, roughly but not exactly abutting: 0.22 m is inside SNAP_RADIUS of the
	# place it belongs, and half a stone out of true is exactly the error a mouse leaves behind.
	var off := 0.22
	var b := _wall([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4),
			Vector3.ZERO], 3.0, 42)
	b.style = st
	b.generate_collision = false
	b.position = far + Vector3(6.0 + depth + off, 0, 0)
	await process_frame
	await process_frame

	var anc := GladeAnchor.gather(b)
	_check(not anc.planes.is_empty(), "anchor: gathered no faces from a wall 0.37 m away")

	# A's face plane is its OUTER SURFACE, x = 6 + depth/2, because the claim was already fattened by
	# half a wall. For B's stone to abut it, B's CENTRELINE stands half of B's own thickness further
	# out: x = 6 + depth. THE OFFSET IS THE WHOLE POINT — snapping a centreline onto a face plane
	# buries half of B inside A, and adding a second half-thickness for A puts it a wall out in the
	# open. Both of those were written before this line held them to a millimetre.
	var want: float = far.x + 6.0 + depth
	var q := far + Vector3(6.0 + depth + off, 1.0, 2.0)
	var got: Dictionary = anc.snap_point(q)
	_check(String(got.get("kind", "")) != "", "anchor: nothing snapped %.2f m off a face" % off)
	_check(absf((got.pos as Vector3).x - want) < 0.001,
			"anchor: snapped to x %.3f, wanted %.3f (one wall thickness off A's face)"
			% [(got.pos as Vector3).x, want])

	# CONTROL — out of range, the cursor is returned untouched. Without this the suite passes on code
	# that snaps everything to everything, which is worse than no snapping at all.
	var free_p := far + Vector3(6.0 + depth + 3.0, 1.0, 2.0)
	var free_r: Dictionary = anc.snap_point(free_p)
	_check((free_r.pos as Vector3).is_equal_approx(free_p),
			"anchor CONTROL: a point 3 m clear of every face was moved anyway")
	_check(String(free_r.get("kind", "")) == "",
			"anchor CONTROL: a point 3 m clear reported a match")

	# CONTROL — distance really is what bounds the candidate set.
	var lonely := _wall([Vector3.ZERO, Vector3(3, 0, 0)], 3.0, 43)
	lonely.style = st
	lonely.generate_collision = false
	lonely.position = far + Vector3(300, 0, 300)
	await process_frame
	_check(GladeAnchor.gather(lonely).planes.is_empty(),
			"anchor CONTROL: a wall 300 m from anything still gathered %d faces"
			% GladeAnchor.gather(lonely).planes.size())

	# THE MODULE MUST NOT UNDO THE SNAP. Both quantise; landing a face exactly on a neighbour and
	# then rounding the span to the nearest brick moves it straight back off.
	b.plan_mode = GladeWall.PlanMode.BOX
	b.set_box_plan(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 4.0, 4.0)
	await process_frame
	var target := b.to_local(Vector3(want, 0.0, far.z + 2.0))
	_check(b.push_face(3, target, 0.0), "anchor: push_face(step 0) refused a BOX plan")
	await process_frame
	var flush_x: float = b.to_global((b.box_plan() as Dictionary).origin as Vector3).x
	_check(absf(flush_x - want) < 0.001,
			"anchor: with the module off the face landed at %.3f, wanted %.3f" % [flush_x, want])

	b.set_box_plan(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 4.0, 4.0)
	await process_frame
	_check(b.push_face(3, target, b.snap_step()), "anchor: push_face(module) refused a BOX plan")
	await process_frame
	var moduled_x: float = b.to_global((b.box_plan() as Dictionary).origin as Vector3).x
	# CONTROL — and the two numbers must actually DIFFER, or the assertion above proves nothing.
	_check(absf(moduled_x - flush_x) > 0.001,
			"anchor CONTROL: the brick module and the anchor agreed, so this pins nothing")

	# ...and the family rule, which is the whole reason GladeBuilding can exist at all.
	var bldg := GladeBuilding.new()
	root.add_child(bldg)
	bldg.position = far + Vector3(0, 0, 400)
	var lo := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 3.0, 44)
	lo.style = st
	lo.generate_collision = false
	var hi := _wall([Vector3.ZERO, Vector3(3, 0, 0), Vector3(3, 0, 3), Vector3(0, 0, 3),
			Vector3.ZERO], 3.0, 45)
	hi.style = st
	hi.generate_collision = false
	hi.junction_rank = 4
	await process_frame
	lo.reparent(bldg)
	hi.reparent(bldg)
	lo.position = Vector3.ZERO
	# STRADDLING `lo`'s FAR WALL, not sitting in its courtyard. A GladeWall lays stone along its
	# PERIMETER, so a claim floating in the middle of the plan overlaps nothing at all and the whole
	# test measures two buildings politely ignoring each other. `hi` spans z 4..7 across `lo`'s z = 5.
	hi.position = Vector3(2.0, 0, 4.0)
	lo.rebuild()
	hi.rebuild()
	await process_frame
	await process_frame
	var siblings := _bricks(lo).size()

	# SIBLINGS ARE NOT FAMILY. `_is_family` is ancestor/descendant, so grouping walls under one node
	# leaves every junction between them exactly as it was at scene root — which is what makes a
	# grouping node a safe thing to ship.
	hi.reparent(lo)                              # ...and THIS is family, and kills the junction
	hi.position = Vector3(2.0, 0, 4.0)
	lo.rebuild()
	await process_frame
	await process_frame
	var nested := _bricks(lo).size()
	_check(nested > siblings,
			"anchor: nesting a wall INSIDE another did not stop the cut (%d bricks vs %d) — either "
			% [nested, siblings] + "the family rule changed or the fixture never junctioned")

	lonely.free()
	bldg.free()
	b.free()
	a.free()
	_done("anchor")


## LEDGES — the third answer to "where does a piece go".
##
## An opening is at (arc, height) and goes IN; a prop is at (arc, height) and hangs ON; a ledge is at
## (arc, height) and stands OFF. A balcony, a gallery, an awning, a lean-to and an external stair are
## one primitive with different parts switched on, which is why this is a domain and not six
## features. BALCONY is what ships first.
func _ledge_suite() -> void:
	var far := Vector3(1700, 0, 1700)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var depth: float = st.depth
	var deck_y := 3.0
	var proj := 1.2

	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 5.0, 51)
	w.style = st
	w.generate_collision = false
	w.position = far
	await process_frame
	await process_frame
	var bare := _bricks(w)
	var bare_out := _outboard(w, far, 6.0 + depth * 0.5 + 0.3, deck_y)

	var L := GladeLedge.new()
	L.position = Vector3(6.0, deck_y, 2.5)      # on the +X wall, three metres up
	L.width = 2.4
	L.project = proj
	w.add_child(L)
	await process_frame
	await process_frame
	var withL := _bricks(w)

	# THE ADDITIVE GUARANTEE, the same one the valley and tee rules are held to: a ledge may add
	# anything it likes and must not move or delete one stone of the wall it hangs on.
	var kept := {}
	for k in withL:
		kept[k] = true
	var lost := 0
	for k in bare:
		if not kept.has(k):
			lost += 1
	_check(lost == 0, "ledge: the balcony moved or deleted %d of the wall's own stones" % lost)
	_check(withL.size() > bare.size(), "ledge: the balcony added nothing at all")

	# WHERE. Pieces standing clear of the wall face exist with a balcony and do not without one.
	var out_n := _outboard(w, far, 6.0 + depth * 0.5 + 0.3, deck_y)
	_check(bare_out == 0, "ledge CONTROL: a bare wall already had %d pieces out in the air"
			% bare_out)
	_check(out_n > 0, "ledge: nothing stands off the wall — the one axis this node exists to add")

	# CONTROL — disabling it puts the wall back exactly as it was.
	L.enabled = false
	w.rebuild()
	await process_frame
	_check(_bricks(w) == bare, "ledge CONTROL: enabled = false is not the bare wall")
	L.enabled = true
	w.rebuild()
	await process_frame

	# BALUSTER SPACING DECIDES HOW MANY. Halving the spacing must roughly double them.
	# THE STAGE'S OWN TALLY, not `_bricks()`. A baluster is a socket: with a mesh wired into the
	# style it is an adopted scene node and never reaches the buffer at all, so counting buffer
	# pieces measured 1077 against 1077 and said nothing. `stats["ledges"]` counts what the stage
	# placed however it placed it, which is the question being asked.
	var fine: GladeStyle = st.duplicate()
	fine.baluster_spacing = st.baluster_spacing * 0.5
	L.style = fine
	w.rebuild()
	await process_frame
	var fine_n := int(w.stats.get("ledges", 0))
	L.style = null
	w.rebuild()
	await process_frame
	var coarse_n := int(w.stats.get("ledges", 0))
	_check(coarse_n > 0, "ledge: the stage tallied nothing at all")
	_check(fine_n > coarse_n,
			"ledge: halving baluster_spacing placed %d pieces against %d" % [fine_n, coarse_n])
	# CONTROL — the two spacings must actually be different numbers, or the above pins nothing.
	_check(absf(fine.baluster_spacing - st.baluster_spacing) > 0.01,
			"ledge CONTROL: the two baluster spacings are the same number")

	# THE CLAIM IS PUBLISHED. A balcony is mass standing in the street and the neighbours must see it.
	var near := _wall([Vector3.ZERO, Vector3(3, 0, 0)], 4.0, 52)
	near.style = st
	near.generate_collision = false
	near.position = far + Vector3(9.0, 0, 2.5)
	await process_frame
	var deck_edge := far + Vector3(6.0 + depth * 0.5 + proj - 0.05, deck_y + 0.1, 2.5)
	var seen := false
	for v: GladeVolume in GladeJunction.gather(near):
		if v.aabb().has_point(deck_edge):
			seen = true
	_check(seen, "ledge: a neighbour 3 m away cannot see the balcony at all")
	# CONTROL — and the claim is the SIZE of a balcony, not of the scene. `gather()` is deliberately
	# scene-wide (the distance reject belongs to `GladeAnchor`, not here), so the honest control is on
	# the volume's own extent: it must contain the deck and nothing 400 m away.
	var ledge_vols: Array = L.junction_volumes()
	_check(ledge_vols.size() == 1, "ledge: the marker published %d volumes" % ledge_vols.size())
	if ledge_vols.size() == 1:
		var lv: GladeVolume = ledge_vols[0]
		_check(lv.contains(deck_edge), "ledge: the published claim does not contain its own deck")
		_check(not lv.contains(deck_edge + Vector3(400, 0, 400)),
				"ledge CONTROL: the claim reaches 400 m — it is not a box, it is the world")
		_check(lv.aabb().size.x < 6.0 and lv.aabb().size.z < 6.0,
				"ledge CONTROL: the claim measures %.1f x %.1f m for a 2.4 m balcony"
				% [lv.aabb().size.x, lv.aabb().size.z])

	# A RECESS PUBLISHES A **VOID** — the first one anything in this kit has ever constructed. It is
	# declared in `glade_volume.gd` and honoured in `glade_junction.gd`, and until now no code path
	# reached it. A void beats any rank: a hole is not a negotiation.
	var thru := _wall([Vector3(4, 0, 2.5), Vector3(8, 0, 2.5)], 6.0, 54)
	thru.style = st
	thru.generate_collision = false
	thru.junction_rank = 9                       # HIGHER than the wall the ledge hangs on
	thru.position = far
	await process_frame
	await process_frame
	var solid_n := _bricks(thru).size()
	L.recess = 0.8
	w.rebuild()
	thru.rebuild()
	await process_frame
	await process_frame
	var voided_n := _bricks(thru).size()
	_check(voided_n < solid_n,
			"ledge VOID: a rank-9 wall kept all %d stones through a recess that should have "
			% solid_n + "removed them regardless of rank")
	# CONTROL — with no recess the same wall keeps them.
	L.recess = 0.0
	w.rebuild()
	thru.rebuild()
	await process_frame
	await process_frame
	_check(_bricks(thru).size() == solid_n,
			"ledge VOID CONTROL: recess = 0 still took stone off the higher-ranked wall")

	# A DECK FOLLOWS ITS WALL, not the world axes. `lay_boards` scans in the polygon's own X, so a
	# balcony on a wall running at 45° gets boards along the WALL only because the deck is handed a
	# frame-aligned space and a transform back. On the naive port they run along world X and read as
	# a rug thrown over the rail — this is the assertion that catches it.
	var diag := _wall([Vector3.ZERO, Vector3(5, 0, 5)], 5.0, 55)
	diag.style = st
	diag.generate_collision = false
	diag.position = far + Vector3(0, 0, 60)
	var d2 := GladeLedge.new()
	d2.position = Vector3(2.5, deck_y, 2.5)
	d2.width = 2.0
	d2.project = 1.0
	diag.add_child(d2)
	await process_frame
	await process_frame
	# A TIGHT BAND, and the tightness is the point: the knees below the deck and the rail above it
	# are placed through the same transform, so a window loose enough to admit them passes on THEIR
	# orientation and proves nothing about the boards. Deck boards sit at deck + half their 9 cm
	# thickness; the knees are 12 cm below and the rail a metre above.
	# ...and OFF the wall line, which matters just as much: the wall's own bricks sit at every height
	# including this one, and they are laid along the wall, so they read as skewed whatever the deck
	# does. The curve runs x = z, so distance from it is |x − z| / sqrt(2); half a metre clears the
	# stone (a wall thickness is 0.44) and keeps every board.
	var boards := 0
	var skewed := 0
	for t in diag.snap_transforms:
		if t.origin.y < deck_y - 0.02 or t.origin.y > deck_y + 0.12:
			continue
		if absf(t.origin.x - t.origin.z) < 0.5:
			continue
		boards += 1
		var ax := t.basis.x.normalized()
		if absf(ax.x) > 0.3 and absf(ax.z) > 0.3:
			skewed += 1
	_check(boards > 0, "ledge: the deck laid no boards at all on a 45 degree wall")
	_check(boards > 0 and skewed >= boards * 0.8,
			"ledge: only %d of %d deck boards follow the wall — the rest run along world X, which "
			% [skewed, boards] + "is the axis-aligned planker reading as a rug over the rail")

	diag.free()
	thru.free()

	near.free()
	w.free()
	_done("ledge")


## How many pieces stand further out than `x_min` (world) at roughly `y`. The measurement that
## separates "it added something" from "it added something IN FRONT OF the wall".
func _outboard(w: GladeWall, origin: Vector3, x_min: float, y: float) -> int:
	var n := 0
	for t in w.snap_transforms:
		var p: Vector3 = t.origin + origin
		if p.x > origin.x + x_min and absf(p.y - origin.y - y) < 1.4:
			n += 1
	return n


## ONE BAY GRID — the windows-between-the-beams defect.
##
## `bays_of` carries a warning that two implementations of "where is a bay" is how a window ends up
## half a stud out of true. Both callers obeyed it and they still disagreed, because they passed
## DIFFERENT BOUNDS: the fill runs between `breaks[ri] ± end_inset()` — posts and mitre boxes claim a
## run's ends — while the opening snap passed the raw break offsets. At a square corner with
## `corner_mitre` on (the default) that inset is 0.20 m, so every window on every closed building was
## snapped to a grid a fifth of a metre from the one the studs were built on.
##
## `_timber_suite` cannot see this: it turns `end_posts` and `corner_posts` OFF on a straight OPEN
## wall precisely because they "would inset the run and skew the bay grid". So the fixture here is
## the case that was excluded — a CLOSED box, with every default left alone.
func _bay_grid_suite() -> void:
	var far := Vector3(1800, 0, 1800)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_timber.tres")
	var w := _wall([Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 5), Vector3(0, 0, 5),
			Vector3.ZERO], 3.0, 61)
	w.style = st
	w.generate_collision = false
	w.position = far
	await process_frame
	await process_frame

	var brk: Array[float] = w._wf.breaks
	_check(brk.size() >= 2, "bay_grid: the box wall has no runs")
	var real := GladeFillTimber.bays_for_run(w._ctx, brk, 0, st)
	var raw := GladeFillTimber.bays_of(st, brk[0], brk[1])
	_check(real.size() >= 3, "bay_grid: run 0 divided into %d bays" % maxi(real.size() - 1, 0))

	# CONTROL FIRST, because it is what makes the rest mean anything: on this fixture the inset must
	# actually be non-zero, or "the two grids agree" would be true of a bug too.
	_check(absf(real[0] - raw[0]) > 0.05,
			"bay_grid CONTROL: the run is not inset at all (%.3f vs %.3f) — with no mitre and no "
			% [real[0], raw[0]] + "post this fixture cannot show the defect it exists for")

	# EVERY BAY BOUNDARY CARRIES A STUD. That is the grid the frame is built on, and it is the grid
	# `bays_for_run` must be returning — if it were still answering with the raw bounds, the studs
	# would stand 0.20 m from every one of these.
	var studs: Array[float] = []
	for t in w.snap_transforms:
		var s := t.basis.get_scale()
		if s.y > 1.2 and s.x < 0.35 and t.origin.z < 0.6:      # tall, thin, on the first run
			studs.append(t.origin.x)
	_check(studs.size() >= 2, "bay_grid: found %d studs on run 0" % studs.size())
	var missed := 0
	for i in range(1, real.size() - 1):
		var want: float = real[i]
		var near := false
		for x in studs:
			if absf(x - want) < 0.22:
				near = true
				break
		if not near:
			missed += 1
	_check(missed == 0,
			"bay_grid: %d of %d bay boundaries have no stud on them — the frame is built on a "
			% [missed, maxi(real.size() - 2, 0)] + "different grid than bays_for_run reports")

	# ...and an opening snaps onto that same grid, which is the defect stated the other way round.
	var o := GladeOpening.new()
	o.position = Vector3(2.7, 1.1, 0.0)
	o.width = 1.0
	o.height = 1.0
	o.arched = false
	w.add_child(o)
	await process_frame
	await process_frame
	# READ WHERE THE HOLE ACTUALLY ENDED UP rather than guessing a band: the snap MOVES the opening,
	# which is its whole job, so a hard-coded range tests the fixture instead of the rule. The first
	# version of this failed on a stud sitting correctly on its own bay boundary, 6 cm outside glass
	# the assertion had put in the wrong place.
	var op: Dictionary = {}
	for e in w._ctx.openings:
		op = e
	_check(not op.is_empty(), "bay_grid: the wall never saw the window")
	var gl0: float = float(op.at) - float(op.w) * 0.5
	var gl1: float = float(op.at) + float(op.w) * 0.5

	# THE EDGES OF THE HOLE LAND ON THE GRID. Its left edge is a stud's inner face and its right edge
	# is a bay boundary — that is precisely what the snap promises, and it is false by 0.20 m when the
	# two grids disagree.
	var tw: float = clampf(st.timber_size, 0.04, 0.5)
	var on_grid := false
	for b in real:
		if absf(gl1 - b) < 0.02:
			on_grid = true
	_check(on_grid, "bay_grid: the window's right edge at %.3f is on no bay boundary %s"
			% [gl1, str(real)])

	var crossing := 0
	for t in w.snap_transforms:
		var s := t.basis.get_scale()
		if s.y < 0.9 or t.origin.z > 0.6:
			continue                               # not a full-height member on this run
		if t.origin.y < 1.2 or t.origin.y > 1.9:
			continue                               # not at the glass
		if t.origin.x > gl0 + tw * 0.5 and t.origin.x < gl1 - tw * 0.5:
			crossing += 1
	_check(crossing == 0,
			"bay_grid: %d full-height members stand inside the glass (%.2f..%.2f)"
			% [crossing, gl0, gl1])

	# BRACES LEAN BOTH WAYS, symmetrically about the run. A brace is a rotated box, so its X axis
	# tilts out of horizontal; the SIGN of that tilt is which way it leans. Every brace leaning the
	# same way is the field of parallel diagonals that read as random in the first place.
	# SYMMETRY, on a wall where the MIDDLE bays are braced too.
	#
	# Two things had to be got right here before this test discriminated at all. It is not enough to
	# ask that both lean directions occur — the old rule mirrored exactly one bay, so a wall did have
	# two directions in it. And it is not enough to test the fixture above: only its END bays brace,
	# and for those the old rule's answer (mirror the last one) happens to coincide with the right
	# one. The defect lives in the middle of a long wall, so that is where it is measured, with
	# `brace_chance` at 1.0 so every bay carries one.
	var braced: GladeStyle = st.duplicate()
	braced.brace_chance = 1.0
	var bw := _wall([Vector3(0, 0, 0), Vector3(13, 0, 0)], 3.0, 62)
	bw.style = braced
	bw.generate_collision = false
	bw.position = far + Vector3(0, 0, 40)
	await process_frame
	await process_frame
	var brun := GladeFillTimber.bays_for_run(bw._ctx, bw._wf.breaks, 0, braced)
	var centre: float = (brun[0] + brun[brun.size() - 1]) * 0.5
	var braces := 0
	var wrong := 0
	for t in bw.snap_transforms:
		var ax := t.basis.x.normalized()
		if absf(ax.y) < 0.25 or absf(ax.y) > 0.95:
			continue                               # upright or flat: a stud, a rail, a panel
		if t.origin.z > 0.6:
			continue
		braces += 1
		var want_neg := t.origin.x > centre
		if (ax.y < 0.0) != want_neg:
			wrong += 1
	_check(braces >= 6, "bay_grid: found only %d braces on a 13 m wall braced at 1.0" % braces)
	_check(braces >= 6 and wrong == 0,
			"bay_grid: %d of %d braces lean the wrong way for their side of the run — framing "
			% [wrong, braces] + "braces IN toward the middle from both ends")

	# ...and no brace crosses the rail it is supposed to stop at. A brace spanning sill to top plate
	# passes straight through the mid-rail, which is the crossing a close-up shows.
	var rail_y: float = st.mid_rail
	var through := 0
	for t in bw.snap_transforms:
		var ax := t.basis.x.normalized()
		if absf(ax.y) < 0.25 or absf(ax.y) > 0.95 or t.origin.z > 0.6:
			continue
		var half_h: float = absf(t.basis.get_scale().x * ax.y) * 0.5
		if t.origin.y - half_h < rail_y - 0.06 and t.origin.y + half_h > rail_y + 0.06:
			through += 1
	_check(through == 0,
			"bay_grid: %d braces run straight through the mid-rail at y %.2f" % [through, rail_y])

	bw.free()
	w.free()
	_done("bay_grid")


## THE BRIDGE VERBS — a wall's own thickness, and its run bent over an arc.
##
## `depth_override` lets one stone style serve a 3.6 m bridge body and a 0.28 m parapet; what it has
## to guarantee is not the number but the AGREEMENT — the fill, the claim and the collision must all
## believe the same thickness, which is why it resolves once in `resolved_style()`. `camber` is a
## humpback: it rides the ground mechanism, so it inherits the course quantisation, and the deck
## STEPS over the hump the way real bridge masonry does.
func _bridge_suite() -> void:
	var far := Vector3(1900, 0, 1900)
	var st: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _wall([Vector3.ZERO, Vector3(12, 0, 0)], 3.0, 71)
	w.style = st
	w.generate_collision = false
	w.position = far
	await process_frame
	await process_frame
	var flat := _bricks(w)
	var base_claim: GladeVolume = w.junction_volumes()[0]

	# CONTROL FIRST: assigning the defaults is indistinguishable from never touching them.
	w.camber = 0.0
	w.depth_override = 0.0
	w.rebuild()
	await process_frame
	_check(_bricks(w) == flat, "bridge CONTROL: assigning the defaults moved stone")

	# THE HUMP. Mid-run stands ~camber above the ends, top and bottom together.
	w.camber = 1.2
	w.rebuild()
	await process_frame
	var mid_y := _mean_y_arc(w, 5.0, 7.0)
	var end_y := (_mean_y_arc(w, 0.0, 1.5) + _mean_y_arc(w, 10.5, 12.0)) * 0.5
	_check(mid_y - end_y > 0.8 and mid_y - end_y < 1.6,
			"bridge: mid-run rose %.2f m for a 1.2 m camber" % (mid_y - end_y))
	var flat_mid := _mean_y_arc_of(flat, 5.0, 7.0)
	var flat_end := (_mean_y_arc_of(flat, 0.0, 1.5) + _mean_y_arc_of(flat, 10.5, 12.0)) * 0.5
	_check(absf(flat_mid - flat_end) < 0.15,
			"bridge CONTROL: the flat wall already humps by %.2f m" % absf(flat_mid - flat_end))

	# ...IN WHOLE COURSES. The camber inherits the terracing quantisation: every column's lift off
	# the flat wall is a multiple of the course height, or the hump is a shear and not masonry.
	# Windows are centred ON the ground-sample keys: `GladeGround.at` snaps a query to its nearest
	# metre, so a window from 3.0 to 4.0 straddles TWO keys and averages two different course
	# multiples into a fraction — which is a fact about the ruler, not the wall. Measured before this
	# was understood: 6 of 12 "ragged" columns on a perfectly stepped hump.
	var ch: float = st.course_height
	var ragged := 0
	for col in range(1, 12):
		var lift := _mean_y_arc(w, float(col) - 0.45, float(col) + 0.45) 				- _mean_y_arc_of(flat, float(col) - 0.45, float(col) + 0.45)
		if absf(lift - roundf(lift / ch) * ch) > 0.05:
			ragged += 1
	_check(ragged <= 2,
			"bridge: %d of 11 key-centred columns lifted by a fraction of a course — the hump is "
			% ragged + "shearing, not stepping")

	# THE THICKNESS, and the agreement about it. The claim's polygon fattens by the override and its
	# `face_depth` reports it — that pair is what the snap and the junctions read.
	w.camber = 0.0
	# ...with the CAP COURSE on: `alsace_stone` ships with it off, and the "the top is paved through"
	# assertion below measured 0 pieces of a surface the fixture was never laying. A control that can
	# only fail is as useless as one that can only pass.
	var capped: GladeStyle = st.duplicate()
	capped.cap_course = true
	w.style = capped
	w.depth_override = 1.3
	w.rebuild()
	await process_frame
	var thick_claim: GladeVolume = w.junction_volumes()[0]
	_check(absf(thick_claim.face_depth - 1.3) < 0.001,
			"bridge: the claim reports face_depth %.2f for an override of 1.3" % thick_claim.face_depth)
	var grew: float = thick_claim.aabb().size.z - base_claim.aabb().size.z
	_check(absf(grew - (1.3 - st.depth)) < 0.1,
			"bridge: the claim fattened by %.2f m for an override %.2f m past the style" 			% [grew, 1.3 - st.depth])
	# TWO LEAVES, NOT STRETCHED STONES. Past LEAF_SPLIT the masonry lays a skin at each face with an
	# honest hollow between — no piece may span the wall, and both faces must actually be there.
	var deep := 0.0
	var near_face := 0
	var far_face := 0
	for t in w.snap_transforms:
		deep = maxf(deep, t.basis.z.length())
		if t.origin.z > 0.25:
			near_face += 1
		elif t.origin.z < -0.25:
			far_face += 1
	_check(deep < 0.85,
			"bridge: a piece spans %.2f m of a 1.3 m wall — stretched stone, not a leaf" % deep)
	_check(near_face > 20 and far_face > 20,
			"bridge: the two faces hold %d and %d pieces — one leaf is missing" 			% [near_face, far_face])
	# ...and the surfaces that WRAP the wall are filled THROUGH: the cap course paves the full
	# depth in rows, so the top carries pieces between the leaves too. A slot here is the hollow
	# showing, which is the one place it must not.
	var mid_top := 0
	for t in w.snap_transforms:
		if absf(t.origin.z) < 0.22 and t.origin.y > 2.7:
			mid_top += 1
	_check(mid_top > 4,
			"bridge: only %d cap pieces between the leaves — the top has a slot into the hollow"
			% mid_top)
	# CONTROL — the flat 0.44 m wall is a single centred line of stone.
	var spread := 0.0
	for e2 in flat:
		var pz := float(String(e2).split(",")[2].split("|")[0])
		spread = maxf(spread, absf(pz))
	_check(spread < 0.3,
			"bridge CONTROL: the thin wall's stone strays %.2f m off the centreline" % spread)

	# AN ARCHED HOLE IS NOT A RECTANGLE, and the CAVITY IS SHUT AT THE REVEAL. Both are about the
	# same 1.3 m wall: put an arch through it and check that (a) the spandrel above the springing
	# still carries stone, and (b) the core between the leaves is closed beside the hole, or the
	# passage shows its own hollow.
	var arch := GladeOpening.new()
	arch.position = Vector3(6.0, 0.0, 0.0)
	arch.width = 2.0
	arch.height = 1.2
	arch.arched = true
	w.add_child(arch)
	await process_frame
	await process_frame
	var spandrel := 0
	var closer := 0
	for t in w.snap_transforms:
		# above the springing, out at the opening's own edge: the corner a square cut would empty
		if t.origin.y > 1.35 and t.origin.y < 1.6 and absf(absf(t.origin.x - 6.0) - 0.95) < 0.3:
			spandrel += 1
		# ...and stone spanning the CORE beside the jamb, which is the cavity being shut
		if absf(t.origin.z) < 0.2 and t.basis.z.length() > 0.3 				and absf(absf(t.origin.x - 6.0) - 1.2) < 0.5 and t.origin.y < 1.4:
			closer += 1
	_check(spandrel > 0,
			"bridge: the spandrel above the arch springing is empty — the cut is square, so the "
			+ "ring hangs in a rectangular void")
	_check(closer > 0,
			"bridge: nothing closes the cavity beside the arch — the reveal shows the hollow core")
	arch.free()
	w.rebuild()
	await process_frame

	# CONTROL — back at zero the claim is the style's own.
	w.depth_override = 0.0
	w.rebuild()
	await process_frame
	_check(absf((w.junction_volumes()[0] as GladeVolume).face_depth - st.depth) < 0.001,
			"bridge CONTROL: override 0 does not read the style's depth back")

	w.free()
	_done("bridge")


func _mean_y_arc(w: GladeWall, a0: float, a1: float) -> float:
	return _mean_y_arc_of(_bricks_pos(w), a0, a1)


func _bricks_pos(w: GladeWall) -> Array:
	var out: Array = []
	for t in w.snap_transforms:
		out.append(t.origin)
	return out


## Mean piece height over an arc window. The fixture's run lies along local X, so arc == x.
func _mean_y_arc_of(data, a0: float, a1: float) -> float:
	var total := 0.0
	var n := 0
	for e in data:
		var x: float
		var y: float
		if e is Vector3:
			x = e.x
			y = e.y
		else:
			var parts: PackedStringArray = String(e).split(",")
			x = float(parts[0])
			y = float(parts[1])
		if x < a0 or x > a1:
			continue
		total += y
		n += 1
	return total / maxf(float(n), 1.0)


## PAINT, NOT GEOMETRY. A band recolours a stretch of wall and changes nothing about its form.
func _paint_suite() -> void:
	var far := Vector3(1200, 0, 1200)
	var plan := [Vector3.ZERO, Vector3(6, 0, 0), Vector3(6, 0, 4), Vector3(0, 0, 4), Vector3.ZERO]
	var plain: GladeStyle = load("res://addons/gladekit/styles/alsace_stone.tres")
	var w := _styled(plan, plain, 3.0, 8)
	w.position = far
	w.generate_collision = false
	w.rebuild()
	await process_frame
	var before := _bricks(w)

	var painted: GladeStyle = plain.duplicate()
	painted.paint_bands = PackedVector2Array([Vector2(1.0, 2.0)])
	painted.paint_band_colors = [Color(0.1, 0.2, 0.9)] as Array[Color]
	painted.paint_band_blend = 1.0
	w.style = painted
	w.rebuild()
	await process_frame

	var inside_blue := 0
	var outside_blue := 0
	for i in w.snap_transforms.size():
		var y := w.snap_transforms[i].origin.y
		var c := w.snap_colors[i]
		var blue: bool = c.b > c.r * 1.5
		# A stone is painted by the height of its course BASE and then sits half a course above it,
		# so the two windows leave a course of dead zone at each edge instead of meeting.
		if y > 1.3 and y < 1.9:
			if blue:
				inside_blue += 1
		elif (y < 0.7 or y > 2.4) and blue:
			outside_blue += 1
	_check(inside_blue > 0, "paint: no stone inside the band took the paint")
	_check(outside_blue == 0,
			"paint: %d stones OUTSIDE the band were painted — a band has edges" % outside_blue)

	# CONTROL — no bands, nothing changes
	w.style = plain
	w.rebuild()
	await process_frame
	_check(_bricks(w) == before, "paint CONTROL: an empty band array changed the wall")

	w.free()
	_done("paint")


## The one MeshInstance3D an adobe wall grows, or null. Deliberately skips MultiMeshInstance3D:
## those are pieces, and this mode has none.
func _adobe_mesh(w: GladeWall) -> Mesh:
	for c in w.get_children(true):
		if c is MeshInstance3D and not (c is MultiMeshInstance3D):
			return (c as MeshInstance3D).mesh
	return null


func _roof_tile_mesh(r: GladeRoof) -> Mesh:
	for c in r.get_children(true):
		if c is MultiMeshInstance3D:
			return (c as MultiMeshInstance3D).multimesh.mesh
	return null


## Mean distance from the plan centre of the stones in a height band — how wide the tower is there.
## Mean local X of every brick standing between two heights. The measurement a shear shows up in:
## a lean displaces a course by an amount proportional to how high it is, so two bands at different
## heights must move by different, PREDICTABLE amounts — which is what separates "it leans" from
## "something moved".
func _mean_x_between(w: GladeWall, y0: float, y1: float) -> float:
	var total := 0.0
	var n := 0
	for t in w.snap_transforms:
		if t.origin.y < y0 or t.origin.y > y1:
			continue
		total += t.origin.x
		n += 1
	return total / maxf(float(n), 1.0)


## How far the furthest corner of a claim polygon stands from a point, in plan.
func _poly_reach(poly: PackedVector2Array, from: Vector2) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, (p - from).length())
	return r


func _radius_between(w: GladeWall, y0: float, y1: float) -> float:
	var total := 0.0
	var n := 0
	for t in w.snap_transforms:
		if t.origin.y < y0 or t.origin.y > y1:
			continue
		total += Vector2(t.origin.x, t.origin.z).length()
		n += 1
	return total / maxf(float(n), 1.0)


## A block with a gable roof on it, for the seam suites. Returns the wall; the roof is child 0.
func _roofed_block(at: Vector3, span: float, deep: float, height: float, pitch: float,
		seed_v: int) -> GladeWall:
	var w := _wall([Vector3.ZERO, Vector3(span, 0, 0), Vector3(span, 0, deep),
			Vector3(0, 0, deep), Vector3.ZERO], height, seed_v)
	w.position = at
	w.generate_collision = false
	var r := GladeRoof.new()
	r.pitch_degrees = pitch
	r.overhang = 0.45
	r.rng_seed = seed_v
	r.eave_brackets = false
	w.add_child(r)
	return w


## Every shingle of a roof as one sorted signature, the way `_bricks` does for a wall.
func _tiles(r: GladeRoof) -> Array[String]:
	var out: Array[String] = []
	for i in r.snap_transforms.size():
		var t := r.snap_transforms[i]
		out.append("%.2f,%.2f,%.2f|%.2f|%s" % [t.origin.x, t.origin.y, t.origin.z,
				t.basis.get_scale().x, r.snap_colors[i].to_html(false)])
	out.sort()
	return out


func _floor_storey(h: float, slab: bool, st: GladeStyle) -> GladeStorey:
	var s := GladeStorey.new()
	s.height = h
	s.style = st
	s.floor_slab = slab
	return s


# --- the mass arris ------------------------------------------------------------------------
#
# A `GladeMass` is the first node whose intent IS a volume, and the only genuinely new thing about
# it is what happens where two FACES meet. Filling a flat face is not new — the strategies have
# tiled a 2-D domain since the first brick, and `GladeSurfacePlanar` hands them the same rectangle
# a wall does. THE ARRIS IS THE TEST.
#
# It is the same rule as `_corner_suite`, which is the point: `GladeStageCorners.quoin_stack()` has
# taken its two arm directions as arguments since it was generalised for the wall tee, so a face
# pair is simply its third caller.

const MASS_SIZE := Vector3(4.0, 3.0, 4.0)
const MASS_FACE_A := 0                         ## -X
const MASS_FACE_B := 4                         ## -Z
## Forgives the jitter every masonry style has by design — tilt, offset and depth jitter let stones
## in one course kiss by a millimetre or two, and that is the look. It does not forgive a stone
## standing a substantial fraction of its own thickness inside another.
const MASS_TOLERANCE := 0.02


func _mass(a: GladeStyle, b: GladeStyle, all_four := false) -> GladeMass:
	var m := GladeMass.new()
	m.size = MASS_SIZE
	if all_four:
		m.style_left = a                       # -X
		m.style_right = b                      # +X
		m.style_front = b                      # -Z
		m.style_back = a                       # +Z
	else:
		# Only the two faces that share the tested arris are built; the other two stay bare, which is
		# also the case that proves a face with ONE built neighbour is inset at one end only.
		m.style_left = a                       # -X
		m.style_front = b                      # -Z
	root.add_child(m)
	return m


## Pieces standing inside other pieces, counted over ALL pairs.
##
## NOT over two classified buckets. Classifying first is what let the control pass while the rule
## was broken: with the mitre off the face stones grow INTO the corner box, land where a quoin
## stands, get filed as quoins, and are then never compared against anything. A piece is a piece.
##
## `below` cuts the scan off under a height, which is how the FIELD is tested apart from what rides
## on top of it — see the cap-course note in the suite.
func _mass_clashes(m: GladeMass, below := 1e9) -> Array:
	var all: Array[Transform3D] = []
	for t in m.snap_transforms:
		if t.origin.y < below:
			all.append(t)
	var pairs := 0
	var worst := 0.0
	for i in all.size():
		for j in range(i + 1, all.size()):
			var p := all[i]
			var q := all[j]
			if p.origin.distance_squared_to(q.origin) > 1.5:
				continue                       # cheap reject; nothing that far apart can overlap
			var o := _box_overlap(p, q)
			if o > MASS_TOLERANCE:
				pairs += 1
				worst = maxf(worst, o)
	return [pairs, worst]


## Penetration depth of two oriented boxes along their axis of least overlap, 0 when apart. Every
## GladeKit piece is a unit cube scaled by its transform, so the basis lengths ARE the extents.
func _box_overlap(a: Transform3D, b: Transform3D) -> float:
	var best := INF
	for t: Transform3D in [a, b]:
		for axis in 3:
			var n: Vector3 = t.basis[axis].normalized()
			var d := absf((b.origin - a.origin).dot(n))
			var gap := _box_extent(a, n) + _box_extent(b, n) - d
			if gap <= 0.0:
				return 0.0                     # a separating axis: they do not touch
			best = minf(best, gap)
	return best


func _box_extent(t: Transform3D, n: Vector3) -> float:
	return 0.5 * (absf(t.basis.x.dot(n)) + absf(t.basis.y.dot(n)) + absf(t.basis.z.dot(n)))


func _mass_arris_suite() -> void:
	var crypt: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres")
	# A second style that is GEOMETRICALLY compatible — same coursing, different colour. That is the
	# case "two styles that blend at the edge" actually means.
	var pale: GladeStyle = crypt.duplicate()
	var pale_palette: Array[Color] = [Color(0.80, 0.76, 0.63), Color(0.71, 0.67, 0.55),
			Color(0.86, 0.82, 0.70)]
	pale.palette = pale_palette
	pale.palette_weights = PackedFloat32Array([3, 2, 2])

	# THE CONTROL FIRST. `corner_mitre` off means the faces do not stop short, so their stones grow
	# into each other — measured at 33 pairs and 0.220 m on a 0.46 m wall. Without this the first
	# assertion below could be passing on geometry that never could have overlapped.
	var off_a: GladeStyle = crypt.duplicate()
	var off_b: GladeStyle = pale.duplicate()
	off_a.corner_mitre = false
	off_b.corner_mitre = false
	var control := _mass_clashes(_mass(off_a, off_b), MASS_SIZE.y)
	_check(int(control[0]) > 0,
			"mass_arris CONTROL: unmitred faces should drive stone through stone")

	var m := _mass(crypt, pale)
	_check(not m.snap_transforms.is_empty(), "mass_arris: the mass built nothing at all")
	_check(int(m.stats.get("faces", 0)) == 2, "mass_arris: expected 2 built faces")
	_check(int(m.stats.get("quoins", 0)) > 0, "mass_arris: the arris was left unquoined")

	# 1. NO STONE THROUGH STONE, in the FIELD.
	#
	# Scanned below the wall top on purpose. The cap course is laid `depth * 1.22` deep — 22% wider
	# than the wall it crowns — and two faces each cap to their own inset, so their copings clip each
	# other at the corner by about 4 cm at y = 3.06. On a WALL that never appears, because one curve
	# carries its cap continuously round the turn; two independent faces have no such luck. It is the
	# same family as roadmap A10 (the trimmings do not know what the field knows) and it wants a
	# coping-corner rule, not a wider tolerance here. Pinned separately below so it cannot get worse.
	var field := _mass_clashes(m, MASS_SIZE.y)
	_check(int(field[0]) == 0,
			"mass_arris: %d pieces stand inside each other in the field (worst %.3f m)"
					% [field[0], field[1]])
	var whole := _mass_clashes(m)
	_check(float(whole[1]) < 0.06,
			"mass_arris: the cap-course corner clash grew to %.3f m (was 0.042)" % whole[1])

	# 2. NO OPEN NOTCH — every course carries a corner stone.
	var cx := -MASS_SIZE.x * 0.5 + crypt.depth * 0.5
	var cz := -MASS_SIZE.z * 0.5 + pale.depth * 0.5
	var quoins: Array[Transform3D] = []
	for t in m.snap_transforms:
		if absf(t.origin.x - cx) < 0.06 and absf(t.origin.z - cz) < 0.06:
			quoins.append(t)
	var courses := int(round(MASS_SIZE.y / crypt.course_height))
	var have := {}
	for t in quoins:
		have[int(floor(t.origin.y / crypt.course_height))] = true
	_check(have.size() >= courses,
			"mass_arris: only %d of %d courses carry a quoin" % [have.size(), courses])

	# 3. THE BEDS MEET. Two styles on one course datum must land at the same heights, or the edge
	# does not blend — which is the whole of what was asked for.
	var beds_a := {}
	var beds_b := {}
	for t in m.snap_transforms:
		if absf(t.origin.x - cx) < 0.06 and absf(t.origin.z - cz) < 0.06:
			continue                           # a quoin belongs to both faces
		if absf(t.origin.x - cx) < crypt.depth:
			beds_a[snappedf(t.origin.y, 0.005)] = true
		elif absf(t.origin.z - cz) < pale.depth:
			beds_b[snappedf(t.origin.y, 0.005)] = true
	var unmatched := 0
	for y: float in beds_a:
		if not beds_b.has(y):
			unmatched += 1
	_check(beds_a.size() > 4 and unmatched == 0,
			"mass_arris: %d of %d bed heights on face A have no match on face B"
					% [unmatched, beds_a.size()])

	# 4. THE QUOIN ALTERNATES, which is what makes a corner read as toothed rather than as a pilaster
	# — and, with two styles, is also what makes it the transition between them.
	quoins.sort_custom(func(p, q): return p.origin.y < q.origin.y)
	var flips := 0
	for i in range(1, quoins.size()):
		if absf(quoins[i].basis.x.normalized().dot(quoins[i - 1].basis.x.normalized())) < 0.7:
			flips += 1
	_check(quoins.size() >= 4 and flips >= quoins.size() - 2,
			"mass_arris: quoins do not alternate (%d stones, %d flips)" % [quoins.size(), flips])

	# 5. ALL FOUR SIDES: every face is then inset at BOTH ends and all four arrises are cut. A
	# two-face case can pass while a face with two built neighbours quietly loses its far end.
	var four := _mass(crypt, pale, true)
	_check(int(four.stats.get("faces", 0)) == 4, "mass_arris: expected 4 built faces")
	_check(int(four.stats.get("quoins", 0)) >= courses * 4,
			"mass_arris: %d quoins across four corners, expected at least %d"
					% [four.stats.get("quoins", 0), courses * 4])
	_check(int(_mass_clashes(four, MASS_SIZE.y)[0]) == 0,
			"mass_arris: four dressed faces clash in the field")

	# 6. A MASS CLAIMS ITS OWN SPACE — one volume, not reconstructed from anything.
	var vols: Array = m.junction_volumes()
	_check(vols.size() == 1, "mass_arris: a box should publish exactly one claim volume")
	_check((vols[0] as GladeVolume).contains(m.global_position + Vector3(0, MASS_SIZE.y * 0.5, 0)),
			"mass_arris: the claim does not contain its own centre")

	# 7. EVERY BASIC FORM, and the one number that decides whether its edges are corners. A hexagon
	# turns 60 degrees at each joint and gets quoined; a 20-gon turns 18 and reads round. Same
	# `corner_angle_deg` threshold a wall uses to decide what a fold is.
	var hex := _prism(crypt, 6)
	_check(int(hex.stats.get("faces", 0)) == 6, "mass_arris: a 6-sided prism should build 6 faces")
	_check(int(hex.stats.get("quoins", 0)) > 0, "mass_arris: a hexagon's 60-degree edges are corners")
	var round_tower := _prism(crypt, 20)
	_check(int(round_tower.stats.get("bricks", 0)) > 0,
			"mass_arris: a 20-sided prism built NOTHING — the phantom inset is back")
	_check(int(round_tower.stats.get("quoins", 0)) == 0,
			"mass_arris: an 18-degree edge is not a corner and must not be quoined")

	# 8. THE DRAG VERBS, driven directly — which is the whole reason they live on the node and not on
	# the gizmo, which no headless test can execute.
	var d := _mass(crypt, crypt)
	var far_before := d.position.x - d.size.x * 0.5
	_check(d.push_face(1, Vector3(4.0, 0.0, 0.0)), "mass_arris: push_face refused on a box")
	_check(absf((d.position.x - d.size.x * 0.5) - far_before) < 0.001,
			"mass_arris: pushing one face moved the OPPOSITE face; it must stay put")
	d.shape = GladeMass.Shape.PRISM
	_check(not d.push_face(1, Vector3(4.0, 0.0, 0.0)),
			"mass_arris: a prism must refuse a face push — it cannot store an irregular polygon")
	d.shape = GladeMass.Shape.BOX
	d.set_solid_height(3.44)
	var n_courses := roundf(d.size.y / crypt.course_height)
	_check(absf(d.size.y - n_courses * crypt.course_height) < 0.001,
			"mass_arris: the height pearl must land on whole courses, got %.3f" % d.size.y)

	# 9. SCALING MAKES IT BIGGER, IT DOES NOT STRETCH THE STONES. The promise the whole kit makes,
	# and the one a mass was silently breaking until the bake existed.
	var was := d.size.x
	d.scale = Vector3(2.0, 1.0, 1.0)
	d._bake_scale()
	_check(is_equal_approx(d.size.x, was * 2.0) and d.scale.is_equal_approx(Vector3.ONE),
			"mass_arris: scale was not absorbed into size (%.2f -> %.2f, scale %s)"
					% [was, d.size.x, d.scale])

	# 10. A PRISM'S SIDES ARE A RING, so their styles CYCLE. Two entries on a hexagon must alternate:
	# sides 0/2/4 one stone, 1/3/5 the other. Checked by mean colour per side, because that is what
	# "the faces are differentiated" actually means to a viewer.
	var pale2: GladeStyle = crypt.duplicate()
	var one: Array[Color] = [Color(0.86, 0.82, 0.68)]
	pale2.palette = one
	pale2.palette_weights = PackedFloat32Array([1])
	var ring := _prism(crypt, 6)
	var ring_styles: Array[GladeStyle] = [crypt, pale2]
	ring.side_styles = ring_styles
	ring.rebuild()
	var means := {}
	for i in ring.snap_transforms.size():
		var o := ring.snap_transforms[i].origin
		var side := int(round((atan2(o.z, o.x) + PI) / TAU * 6.0)) % 6
		if not means.has(side):
			means[side] = [Color(0, 0, 0), 0]
		means[side][0] += ring.snap_colors[i]
		means[side][1] += 1
	var dark := 0.0
	var light := 0.0
	for k: int in means:
		var mean: Color = means[k][0] / float(means[k][1])
		if k % 2 == 0:
			dark = maxf(dark, mean.r)
		else:
			light = minf(light, mean.r) if light > 0.0 else mean.r
	_check(means.size() >= 6 and light - dark > 0.08,
			"mass_arris: side_styles did not alternate round the ring (even %.2f vs odd %.2f)"
					% [dark, light])

	_done("mass_arris")


## THE PANEL FILL: a textured surface instead of pieces, and the one place in the kit with UVs.
func _panel_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	st.wall_mode = GladeStyle.WallMode.PANEL
	st.panel_uv_scale = 2.0

	# A BENT wall, so the panel has to follow the curve rather than chord straight through it.
	var w := _wall([Vector3(-4, 0, 0), Vector3(0, 0, 0), Vector3(3, 0, 2)], 3.0)
	w.style = st
	w.rebuild()

	var mesh: ArrayMesh = null
	for ch in w.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			mesh = (ch as MeshInstance3D).mesh
	_check(mesh != null, "panel: a PANEL wall committed no mesh at all")
	if mesh == null:
		_done("panel")
		return
	var arrays := mesh.surface_get_arrays(0)
	_check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0, "panel: the mesh is empty")
	# UVs AND TANGENTS. Everything else in the addon is untextured, so this is the one surface that
	# may have either — and a normal map without tangents is a flat wall wearing a confusing picture.
	_check(arrays[Mesh.ARRAY_TEX_UV] != null, "panel: no UVs — a tiling material has nothing to tile")
	_check(arrays[Mesh.ARRAY_TANGENT] != null, "panel: no tangents — normal maps will be wrong")

	# It costs a handful of triangles, not thousands of pieces. That IS the feature.
	_check(w.snap_transforms.size() < 20,
			"panel: a panel wall placed %d instanced pieces; it should place almost none"
					% w.snap_transforms.size())

	# AN OPENING STILL SUBTRACTS. The hole is a fact about the domain, not about what fills it, so
	# the panel gets it from the same `clear_rects` every other mode uses.
	var solid_verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var door := GladeOpening.new()
	door.position = Vector3(0, 0, 0)
	door.width = 1.2
	door.height = 2.0
	w.add_child(door)
	w.rebuild()
	var holed := 0
	for ch in w.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			holed = _tri_verts((ch as MeshInstance3D).mesh, 0).size()
	_check(holed > solid_verts,
			"panel: a door did not cut the sheet (%d verts before, %d after — it should SPLIT into more)"
					% [solid_verts, holed])

	# --- PANEL ON A SOLID: a skin, not slabs -------------------------------------------------
	var ps: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres").duplicate()
	ps.wall_mode = GladeStyle.WallMode.PANEL

	# 1. THE SKIN IS CLOSED. Every face of the volume, cap and floor included — the cap being the one
	# that was not merely unstyled but UNBUILDABLE, because the emitter hardcoded world up as the
	# domain's second axis and the surface refused any face that was not upright.
	var solid := GladeMass.new()
	solid.style = ps
	root.add_child(solid)
	solid.rebuild()
	_check(int(solid.stats.get("faces", 0)) == 6,
			"panel: a box skin should cover all 6 faces, got %s" % solid.stats.get("faces", 0))
	var up_n := 0
	var down_n := 0
	for ch in solid.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			for n: Vector3 in ((ch as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
					as PackedVector3Array):
				if n.y > 0.9:
					up_n += 1
				elif n.y < -0.9:
					down_n += 1
	_check(up_n > 0, "panel: the solid has no CAP — the top face was not skinned")
	_check(down_n > 0, "panel: the solid has no floor")

	# 2. NO SLABS. A one-sided surface must be skinned ONCE; skinning it twice put a second sheet
	# inside the block and the pair read as a free-standing slab.
	#
	# COUNTED ON THE MESH, not on the tally. `stats.bricks` counts EMIT CALLS, and a face takes one
	# of two roads — a whole-polygon fan, or a rectangle cut into claim-tested pieces — so the same
	# closed box reports 12 or 6 depending on whether anything nearby could bite it. A stray VOID
	# from the ledge suite was enough to flip it, and the assertion failed on a building that was
	# perfectly correct. Triangles are the thing that is actually invariant.
	var tri := 0
	for ch in solid.get_children(true):
		var mi := ch as MeshInstance3D
		if mi and mi.mesh and not mi.is_queued_for_deletion():
			tri += ((_tri_verts(mi.mesh, 0)
					as PackedVector3Array).size()) / 3
	_check(tri == 12, "panel: a closed box skin is 6 faces x 2 triangles = 12, got %d" % tri)

	# 3. MASONRY IS UNAFFECTED by any of that: it still refuses horizontal faces, because it stacks
	# courses along world up and a cap would lay them into the air. `needs_upright()` is the whole
	# difference, and this is the control that proves the two modes really are asked separately.
	var stone_solid := GladeMass.new()
	stone_solid.style = load("res://addons/gladekit/styles/crypt_stone.tres")
	root.add_child(stone_solid)
	stone_solid.rebuild()
	_check(int(stone_solid.stats.get("faces", 0)) == 4,
			"panel CONTROL: a masonry mass must build 4 upright faces, not %s"
					% stone_solid.stats.get("faces", 0))

	# 4. HOLLOW SHOWS PER-WALL THICKNESS. The depth was always per-face; a solid block had nowhere to
	# display it. Two walls at different depths must produce an interior, and the run must not fail
	# silently — `lining` counts the inner skin and the top frame together.
	var thick: GladeStyle = ps.duplicate()
	thick.depth = 0.6
	var thin: GladeStyle = ps.duplicate()
	thin.depth = 0.2
	var room := GladeMass.new()
	room.style = ps
	room.style_left = thick
	room.style_front = thin
	room.hollow = true
	root.add_child(room)
	room.rebuild()
	_check(int(room.stats.get("lining", 0)) > 0,
			"panel: hollow built no interior at all")
	_check(int(room.stats.get("lining", 0)) > int(solid.stats.get("lining", 0)),
			"panel: hollow should add surfaces a solid block does not have")
	# A HOLLOW SOLID HAS NO LID — the frame replaces the cap. Building both put a full top over the
	# opening and the room vanished behind it, which the first render of this caught.
	_check(int(room.stats.get("faces", 0)) == 5,
			"panel: a hollow box should skin 5 faces (the cap becomes a frame), got %s"
					% room.stats.get("faces", 0))

	# ...and the thickness is really PER WALL. Measured, not eyeballed: the box spans -half..+half,
	# so a wall of depth d puts its inner surface at -half + d. This is the whole point of `hollow`.
	var half_x := room.size.x * 0.5
	var half_z := room.size.z * 0.5
	var seen_thick := false
	var seen_thin := false
	for ch in room.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			for v: Vector3 in _tri_verts((ch as MeshInstance3D).mesh, 0):
				if absf(v.x - (-half_x + thick.depth)) < 0.02:
					seen_thick = true
				if absf(v.z - (-half_z + thin.depth)) < 0.02:
					seen_thin = true
	_check(seen_thick, "panel: the 0.6 m wall's inner surface is not at its own depth")
	_check(seen_thin, "panel: the 0.2 m wall's inner surface is not at its own depth")

	# 5. UNTEXTURED IS VISIBLE. Vertex colours from the palette, so the built-in fallback material
	# (which reads them) shows coloured stone rather than nothing.
	var colours_ok := false
	for ch in solid.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			var cols = (ch as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			if cols != null and (cols as PackedColorArray).size() > 0 \
					and (cols as PackedColorArray)[0].get_luminance() > 0.05:
				colours_ok = true
	_check(colours_ok, "panel: no vertex colours — an untextured panel would be invisible")

	# 6. A STYLELESS MASS DRAWS ITS BLOCK, so a massing you cannot judge is not a thing.
	var blank := GladeMass.new()
	root.add_child(blank)
	blank.rebuild()
	var previews := 0
	for ch in blank.get_children(true):
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
			previews += 1
	_check(previews > 0, "panel: a mass with no style drew nothing at all")
	_done("panel")


## MASSES THAT MERGE — one building out of several boxes, and the same rule inverted for a partition.
##
## MEASURED AFTER A FRAME, always. `queue_free` is deferred, so the generation a rebuild just
## replaced is still in the tree when the call returns; counting meshes immediately counts ghosts and
## reports a wall that did not change as having grown by half. That cost a debugging round here.
func _mass_merge_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")

	# CONTROL FIRST: two overlapping masses that are NOT under a building are two buildings, resolve
	# by rank, and at equal rank ignore each other entirely. This is what keeps every scene built
	# before merging existed untouched.
	var lone := _merge_mass(st, Vector3(0, 0, 0), Vector3(6, 3, 3))
	root.add_child(lone)
	await process_frame
	var lone_stats := (lone.stats as Dictionary).duplicate()
	var intruder := _merge_mass(st, Vector3(0, 0, 2.0), Vector3(3, 3, 4))
	root.add_child(intruder)
	lone.rebuild()
	await process_frame
	_check(int(lone.stats.get("bricks", 0)) == int(lone_stats.get("bricks", 0))
			and int(lone.stats.get("lining", 0)) == int(lone_stats.get("lining", 0)),
			"mass_merge CONTROL: a loose overlapping mass changed the other (%s vs %s) — merging "
					% [lone.stats, lone_stats] + "must require a GladeBuilding")

	# MERGED: the sketch's two boxes, a hall and a wing, under one building.
	var bld := GladeBuilding.new()
	root.add_child(bld)
	var hall := _merge_mass(st, Vector3(40, 0, 0), Vector3(6, 3, 3))
	var wing := _merge_mass(st, Vector3(40, 0, 2.0), Vector3(3, 3, 4))
	bld.add_child(hall)
	bld.add_child(wing)
	hall.rebuild()
	wing.rebuild()
	hall.rebuild()
	await process_frame
	_check(hall.merge_siblings().size() > 0, "mass_merge: the hall sees no merge sibling")
	_check(not _merge_verts(hall).is_empty() and not _merge_verts(wing).is_empty(),
			"mass_merge: a merged box built nothing at all — an empty surface probably aborted "
					+ "the commit")

	# THE INVARIANT: no surface of either box stands inside the other. That IS the T outline —
	# the union boundary is (hall outside wing) + (wing outside hall), so suppression alone traces it.
	# THE FLOOR IS EXCLUDED, and honestly. A floor is one polygon laid in one call, so it cannot be
	# partly suppressed the way a wall is — two merged masses lay overlapping floors across their
	# shared region. Clipping it wants the union polygon, which is exactly what this cycle held in
	# reserve. Walls, linings and copings ARE cut, and those are what the invariant pins.
	var h_in := _merge_inside(hall, wing)
	var w_in := _merge_inside(wing, hall)
	_check(h_in == 0, "mass_merge: %d of the hall's wall surface stands inside the wing" % h_in)
	_check(w_in == 0, "mass_merge: %d of the wing's wall surface stands inside the hall" % w_in)

	# THE FLOOR IS THE ONE SURFACE BOTH BOXES OWN, and it fails in two opposite ways. Deck only the
	# inner footprint and the strip the vanished wall stood on is floored by nobody — the first render
	# of a T showed grass through the join, in an L-shaped band 0.46 m wide. Deck both in full and the
	# shared patch is laid twice, coplanar, which is a z-fight. So: covered EXACTLY ONCE, everywhere
	# inside the union, including the band under a wall that is no longer there.
	var floors := _merge_floor_tris(hall)
	floors.append_array(_merge_floor_tris(wing))
	# ...sampled off every axis of symmetry, so a point cannot land on a triangle's own diagonal and
	# be counted by both halves of a quad.
	for p: Vector2 in [Vector2(38.73, 1.17), Vector2(41.29, 1.23), Vector2(39.87, 0.71),
			Vector2(38.2, -0.9), Vector2(40.1, 3.3)]:
		var cover := _merge_floored(floors, p)
		_check(cover == 1, "mass_merge: %v is floored %d times, not once — 0 is a hole at the join, "
				% [p, cover] + "2 is two decks fighting for it")

	# A PARTITION IS THE SAME TEST WITH A MINUS SIGN: it exists only where it is buried.
	var host_before := (hall.stats as Dictionary).duplicate()
	# WALL TO WALL, with its ends dying INTO the host's stone — which is what a divider does, and the
	# only arrangement that can catch a partition claiming: one floating in mid-room buries none of
	# its host's surface, so the host looks untouched whether the rule is right or wrong.
	var part := _merge_mass(st, Vector3(40, 0, 0), Vector3(0.4, 3, 2.8))
	part.hollow = false
	bld.add_child(part)
	part.partition = true
	part.rebuild()
	hall.rebuild()
	await process_frame
	var out_of_bounds := 0
	for v: Vector3 in _merge_verts(part):
		var toward: Vector3 = hall.global_position + Vector3(0, 1.5, 0)
		if not _merge_in_any(hall.junction_volumes(), v + (toward - v).normalized() * 0.08):
			out_of_bounds += 1
	_check(not _merge_verts(part).is_empty(), "mass_merge: the partition built nothing")
	_check(out_of_bounds == 0,
			"mass_merge: %d of the partition's vertices stick out of the building it divides"
					% out_of_bounds)

	# ...AND YOU CAN WALK FROM ONE ROOM INTO THE OTHER. A merged join takes a wall away, and until
	# this the collider never heard about it: the stone went and the box stayed, so you walked up to
	# an opening you could see straight through and stopped dead. An invisible wall is worse than a
	# visible one, and no render finds it.
	var hall_body := _mass_body(hall)
	var wing_body := _mass_body(wing)
	_check(hall_body != null and wing_body != null, "mass_merge: a merged mass has no collision")
	if hall_body and wing_body:
		# In the mouth, at knee height: neither box may claim it.
		var mouth := Vector3(40.0, 0.9, 1.3)
		_check(not _shape_covers(hall_body, mouth) and not _shape_covers(wing_body, mouth),
				"mass_merge: the join is solid to physics — the wall is gone and its collider is not")
		# ...and the wall well clear of the join is still solid, or the house has no walls.
		_check(_shape_covers(hall_body, Vector3(37.2, 0.9, 0.0)),
				"mass_merge: cutting the collider took the whole wall, not the opening")

	# A PARTITION IS NOT A CLAIM. It adds surface where it is buried and takes NONE — so the room it
	# divides must be exactly the room it was before. Gathered as an ordinary merge sibling it is
	# instead a box standing in the host's wall, and the host dutifully declines to build there: the
	# render showed a partition-shaped hole clean through the outer wall of the hall.
	_check(hall.stats == host_before,
			"mass_merge: adding a partition changed its host (%s -> %s) — a partition must not claim"
					% [host_before, hall.stats])

	# ...AND IT IS ITS OWN SIZE. The claim path fills a rectangle whose second side used to be the
	# SOLID's height rather than the SURFACE's, which is the same number on an upright face and not on
	# a cap: a 0.4 m partition wore a 3 m lid, hanging out over the room it divides.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v: Vector3 in _merge_verts(part):
		lo = lo.min(v)
		hi = hi.max(v)
	_check((hi - lo).distance_to(part.size) < 0.02,
			"mass_merge: the partition measures %v but was built %v" % [part.size, hi - lo])
	# THE CUT LANDS ON THE PLANE, NOT ON A GRID — and the two skins land on DIFFERENT planes, which is
	# the whole of `GladeClaim.Layer`. The hall's outer skin stops at the wing's BOX; its lining runs
	# on across the wing's wall band and stops at the wing's ROOM, half a metre further in. Both used
	# to be decided by whichever 0.25 m piece happened to straddle the boundary, and the two answers
	# disagreed by up to a quarter of a metre: you looked past the edge of the lining at the back of a
	# one-sided sheet, and out at the grass. That is the defect this measures, in millimetres.
	var wing_box: float = wing.position.x - wing.size.x * 0.5
	var wing_room: float = wing_box + GladeUtil.current_style(st).depth
	var skin_cut := _merge_cut(hall, "back", 40.0)
	var line_cut := _merge_cut(hall, "back.inner", 40.0)
	_check(absf(skin_cut - wing_box) < 0.005,
			"mass_merge: the outer skin stops at %.3f, the wing's face is at %.3f"
					% [skin_cut, wing_box])
	_check(absf(line_cut - wing_room) < 0.005,
			"mass_merge: the lining stops at %.3f, the wing's room begins at %.3f"
					% [line_cut, wing_room])

	_done("mass_merge")


## THE FURTHEST A SURFACE GETS toward `mid` from the low side — where its cut actually landed.
func _merge_cut(m: GladeMass, key: String, mid: float) -> float:
	var best := -INF
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if String(m._face_by_mesh.get(mi.name, "")) != key:
			continue
		for v: Vector3 in _tri_verts(mi.mesh, 0):
			var w: Vector3 = m.to_global(v)
			if w.x < mid:
				best = maxf(best, w.x)
	return best


## How far back along z a surface reaches — the end of the wing's lining, toward the hall.
func _merge_reach(m: GladeMass, key: String) -> float:
	var best := INF
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if String(m._face_by_mesh.get(mi.name, "")) != key:
			continue
		for v: Vector3 in _tri_verts(mi.mesh, 0):
			best = minf(best, m.to_global(v).z)
	return best


## IS THERE SURFACE AT THIS SPOT ON THIS FACE? Point-in-triangle in the two world axes the face runs
## in, which for an upright wall are x and y. The only way to ask "is this bit of wall standing" of
## geometry that comes back as however many runs the claim left, rather than one quad per wall.
func _mass_hits(m: GladeMass, key: String, world: Vector3) -> bool:
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if String(m._face_by_mesh.get(mi.name, "")) != key:
			continue
		var verts: PackedVector3Array = _tri_verts(mi.mesh, 0)
		for k in range(0, verts.size() - 2, 3):
			var a: Vector3 = m.to_global(verts[k])
			var b: Vector3 = m.to_global(verts[k + 1])
			var cc: Vector3 = m.to_global(verts[k + 2])
			# ON THE FACE'S OWN TWO AXES. Projecting everything onto world (x, y) collapses a face
			# whose plane IS x to a line, and every test against it answers no — which reads exactly
			# like a missing wall. So the axis the face's normal points down is the one dropped.
			var n := (b - a).cross(cc - a)
			var drop := 0
			if absf(n.y) > absf(n.x) and absf(n.y) >= absf(n.z):
				drop = 1
			elif absf(n.z) > absf(n.x) and absf(n.z) > absf(n.y):
				drop = 2
			if Geometry2D.point_is_inside_triangle(_flat(world, drop), _flat(a, drop),
					_flat(b, drop), _flat(cc, drop)):
				return true
	return false


func _flat(p: Vector3, drop: int) -> Vector2:
	if drop == 0:
		return Vector2(p.y, p.z)
	if drop == 1:
		return Vector2(p.x, p.z)
	return Vector2(p.x, p.y)


## A WING SHORTER THAN ITS HALL. Merging never assumed one height — the claim is a solid and knows
## about y — but every cut was SAMPLED at one height, so a wall was buried all the way up or not at
## all. Whichever way that fell, half the answer was wrong: the first render of a low wing lost the
## hall's entire back wall below the wing's roofline, along its whole length, and you stood outside
## and looked in through it.
func _mass_storey_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")
	var bld := GladeBuilding.new()
	root.add_child(bld)
	# A LONG HALL AND A SHORT WING, and the proportion is the test. Three metres of wing against
	# fourteen of hall is small enough to fall between samples taken at a few places along the wall,
	# which is exactly what happened: the height scan found no roofline, decided the whole wall in one
	# band, and the hall lost its lintel — you stood in the room and saw sky over the join.
	var hall := _merge_mass(st, Vector3(80, 0, 0), Vector3(14, 3, 3))
	# OVERLAPPING BY LESS THAN TWO WALL THICKNESSES (0.5 m against 0.46 + 0.46), which is the other
	# half of this fixture: overlap deeply and the neighbour's room reaches past this one's lining on
	# its own, so the corner closes whether the lining is extended or not.
	var wing := _merge_mass(st, Vector3(76.5, 0, 3.0), Vector3(3, 1.5, 4))
	bld.add_child(hall)
	bld.add_child(wing)
	hall.rebuild()
	wing.rebuild()
	hall.rebuild()
	await process_frame

	# Behind the wing, on the hall's back wall: stone above the wing's roof, none below it.
	_check(_mass_hits(hall, "back", Vector3(76.5, 2.2, 1.5)),
			"mass_storey: the hall's wall is missing above the wing's roofline — a low neighbour "
					+ "must not bury the whole height of a wall")
	_check(not _mass_hits(hall, "back", Vector3(76.5, 0.7, 1.5)),
			"mass_storey: the hall's wall stands inside the wing below its roofline")
	# ...and clear of the wing it is whole from the ground up.
	_check(_mass_hits(hall, "back", Vector3(84.0, 0.7, 1.5)) and _mass_hits(hall, "back", Vector3(84.0, 2.2, 1.5)),
			"mass_storey: the hall's wall is cut where nothing touches it")

	# THE INNER CORNER MEETS. A lining ends where the wall it dies into stands, and at a join that
	# wall is buried — so the room's boundary stopped a wall's thickness short of the neighbour's and
	# left a slot a hand wide and a storey tall with the sky behind it. The wing's own lining has to
	# REACH the plane of the hall's; no amount of cutting can close a gap between two surfaces that
	# both stop early.
	var hall_room: float = hall.position.z + hall.size.z * 0.5 - GladeUtil.current_style(st).depth
	var reach := _merge_reach(wing, "right.inner")
	_check(absf(reach - hall_room) < 0.005,
			"mass_storey: the wing's lining reaches z %.3f and the hall's lining plane is z %.3f — "
					% [reach, hall_room] + "what is between them is a slot you see daylight through")
	_done("mass_storey")


## A DOORWAY THROUGH A PARTITION — a hole in a solid block, which is not the hole a shell takes: it
## cuts BOTH faces and its reveal spans between them. And it is a hole to physics as well, because no
## mass cut its collision around an opening before this: every door in the kit was one you could see
## through and not walk through.
func _mass_door_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")
	var bld := GladeBuilding.new()
	root.add_child(bld)
	var hall := _merge_mass(st, Vector3(120, 0, 0), Vector3(6, 3, 3))
	bld.add_child(hall)
	var part := _merge_mass(st, Vector3(120, 0, 0), Vector3(0.4, 3, 2.8))
	part.hollow = false
	bld.add_child(part)
	part.partition = true
	var o := GladeOpening.new()
	o.position = Vector3.ZERO
	o.width = 0.9
	o.height = 2.0
	part.add_child(o)
	part.rebuild()
	await process_frame

	# BOTH FACES, or the door is a niche on one side and a blank wall on the other.
	for key: String in ["left", "right"]:
		_check(not _mass_hits(part, key, Vector3(120.0, 1.0, 0.0)),
				"mass_door: the partition's %s face is not cut by its opening" % key)
		_check(_mass_hits(part, key, Vector3(120.0, 2.6, 0.0)),
				"mass_door: the partition's %s face has no wall over the door" % key)
	_check(int((part.stats as Dictionary).get("reveals", 0)) > 0,
			"mass_door: the doorway has no reveal — the hole goes through, so its sides must exist")

	# ...AND YOU CAN WALK THROUGH IT.
	var body := _mass_body(part)
	_check(body != null, "mass_door: the partition has no collision at all")
	if body:
		_check(not _shape_covers(body, Vector3(120.0, 1.0, 0.0)),
				"mass_door: the doorway is solid to physics — a door you cannot walk through")
		_check(_shape_covers(body, Vector3(120.0, 1.0, 1.2)),
				"mass_door: the partition beside the door is not solid — cutting the collision took "
						+ "the whole wall instead of the hole")
	# ...AND A DOORWAY IS SOMETHING YOU WALK THROUGH, which is not the same claim as "the collider has
	# a hole in it". A hollow mass stands its floor on a 20 cm slab, so every door presented a KERB
	# with a vertical face, and `CharacterBody3D` does not climb steps — it slides along them. The
	# threshold ramp is what makes the hole walkable, and only a body actually walking finds out.
	var room := _merge_mass(st, Vector3(160, 0, 0), Vector3(6, 3, 5))
	root.add_child(room)
	var d := GladeOpening.new()
	d.position = Vector3(0, 0, -2.5)
	d.width = 1.4
	d.height = 2.1
	room.add_child(d)
	room.rebuild()
	await process_frame
	var got_in: bool = await _walked_in(Vector3(160, 0.02, -6.0), 160.0)
	_check(got_in,
			"mass_door: a body with no step handling could not walk in through the door — the floor "
					+ "slab is a kerb and the threshold ramp is not carrying it over")
	_done("mass_door")


## Walk a plain CharacterBody3D north from `from` and report whether it got past the wall at `x`.
##
## Deliberately the WORST CASE: no step logic, no snap, nothing but `move_and_slide`. Anything a
## project's own controller adds can only help, so a door that passes this passes for everyone.
func _walked_in(from: Vector3, x: float) -> bool:
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(40, 1, 40)
	gs.shape = gb
	gs.position = Vector3(x, -0.5, 0)
	ground.add_child(gs)
	root.add_child(ground)
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	body.add_child(cs)
	root.add_child(body)
	body.global_position = from
	await process_frame
	# LONG ENOUGH TO ARRIVE. `move_and_slide` advances by the PHYSICS delta however often it is called,
	# and a headless tree hands out process frames faster than physics steps — measured at about 2 cm
	# of travel per iteration against the 5 cm the velocity says. At 150 iterations the body was still
	# on the ramp with the wall in front of it, and the suite read "could not get in" for a door it was
	# in the act of walking through. The budget is the walk, not the door.
	for i in 400:
		body.velocity = Vector3(0, -6.0, 3.0)
		body.move_and_slide()
		await process_frame
	var got := body.global_position.z
	body.queue_free()
	ground.queue_free()
	return got > -1.0


## A ROOF STANDS ON A HOST, NOT ON A WALL.
##
## `GladeRoof` read its parent as a `GladeWall` in eight places, so for a long time the one building
## shape that most wants a roof — a solid tower with eight sides — could not have one. Both hosts now
## answer `roof_host()`, and what this pins is that the roof asks nobody what type produced it.
##
## The real test of the extraction is the GOLDEN dump, not anything in here: a wall's roof has to come
## back byte-identical, and 139,979 lines of it do. This suite covers the half golden cannot see.
func _mass_roof_suite() -> void:
	var st: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres")
	# THE HOST IS PANEL, THE ROOF IS MASONRY, and the difference matters to this suite: only a PANEL
	# mass lines itself and lays a coping, so a masonry host would answer the coping questions below
	# with "there was never one" and pass for the wrong reason.
	var panel: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")

	# A BOX GETS A GABLE, and its ridge runs the long way — the same rule a wall's footprint gets.
	var box := GladeMass.new()
	box.style = panel
	box.size = Vector3(8, 3, 4)
	box.position = Vector3(160, 0, 0)
	box.hollow = true
	root.add_child(box)
	var r := GladeRoof.new()
	r.style = st
	r.rng_seed = 3
	box.add_child(r)
	r.rebuild()
	await process_frame
	_check(int(r.stats.get("shingles", 0)) > 50,
			"mass_roof: a roof over a box mass laid %s tiles" % r.stats.get("shingles", 0))
	_check(absf(float(r.stats.get("length", 0.0)) - 8.0) < 0.01
			and absf(float(r.stats.get("span", 0.0)) - 4.0) < 0.01,
			"mass_roof: the ridge does not run the long way (length %s, span %s)"
					% [r.stats.get("length", 0), r.stats.get("span", 0)])

	# ...AND A PRISM GETS A CONE, on AUTO, because a mass with sides says "round" the way a cylinder
	# wall does. Nothing in the roof learned about masses for this to work.
	var tower := GladeMass.new()
	tower.style = panel
	tower.shape = GladeMass.Shape.PRISM
	tower.sides = 8
	tower.size = Vector3(4, 6, 4)
	tower.position = Vector3(180, 0, 0)
	tower.hollow = true
	root.add_child(tower)
	var cone := GladeRoof.new()
	cone.style = st
	cone.rng_seed = 4
	tower.add_child(cone)
	cone.rebuild()
	await process_frame
	_check(String(cone.stats.get("shape", "")) == "cone",
			"mass_roof: an eight-sided mass got %s, not a cone" % cone.stats.get("shape", "none"))
	_check(int(cone.stats.get("segments", 0)) == 8,
			"mass_roof: the cone has %s segments, not the mass's 8" % cone.stats.get("segments", 0))

	# A ROOFED MASS DROPS ITS COPING, exactly as a roofed wall drops its capstones — the strip would
	# otherwise sit inside the eaves and fight the tiles for the same pixels.
	_check(not _mass_has_layer(box, ".top"),
			"mass_roof: a roofed mass still lays its coping, under its own eaves")
	r.visible = false
	box.rebuild()
	await process_frame
	_check(_mass_has_layer(box, ".top"),
			"mass_roof: the coping did not come back when the roof went away")

	# A ROOF ON SOMETHING THAT IS NEITHER builds nothing, and says nothing.
	var orphan := Node3D.new()
	root.add_child(orphan)
	var lost := GladeRoof.new()
	lost.style = st
	orphan.add_child(lost)
	lost.rebuild()
	await process_frame
	_check(int(lost.stats.get("shingles", 0)) == 0,
			"mass_roof: a roof with no host built %s tiles" % lost.stats.get("shingles", 0))
	_done("mass_roof")


## DRESSED CORNERS ON A TEXTURED WALL.
##
## `dresses_corners()` refuses PANEL, and rightly — a rendered wall has no dressed angle unless
## somebody says it does. It was a LAW rather than a default, so a textured mass met its neighbour in
## a mathematically straight line and nothing could stand proud of it. `style_quoin` is that
## somebody: the stone the ARRIS is made of, whatever the faces are made of.
##
## THE INSET IS THE HALF OF THIS THAT BITES. A face that grows a quoin and does not stop short for it
## drives half a stone into its own corner block — measured at 0.220 m on a 0.46 m wall the first
## time, against a predicted 0.23, which is how that arithmetic was found rather than guessed.
func _mass_quoin_suite() -> void:
	var panel: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")
	var stone: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres")

	# CONTROL FIRST: a panel mass with no quoin style is what it always was.
	var bare := _quoin_mass(panel, Vector3(200, 0, 0))
	root.add_child(bare)
	bare.rebuild()
	await process_frame
	var bare_stats := (bare.stats as Dictionary).duplicate()
	_check(int(bare_stats.get("quoins", 0)) == 0,
			"mass_quoin CONTROL: a panel mass grew %s quoins with no quoin style"
					% bare_stats.get("quoins", 0))

	# ...AND WITH ONE, it grows the same stack a masonry box grows.
	var dressed := _quoin_mass(panel, Vector3(220, 0, 0))
	dressed.style_quoin = stone
	root.add_child(dressed)
	dressed.rebuild()
	await process_frame
	var masonry := _quoin_mass(stone, Vector3(240, 0, 0))
	root.add_child(masonry)
	masonry.rebuild()
	await process_frame
	var got := int((dressed.stats as Dictionary).get("quoins", 0))
	var want := int((masonry.stats as Dictionary).get("quoins", 0))
	_check(got > 0, "mass_quoin: a quoin style on a panel mass grew no corner stones")
	_check(got == want,
			"mass_quoin: %d corner stones against masonry's %d — it should be the same stack" % [got, want])

	# THE FILL STOPS SHORT FOR THE BLOCK IT NOW HAS, by the same number the masonry path uses.
	var q_gap := dressed._inset(GladeUtil.current_style(panel), 1, 4)
	var m_gap := masonry._inset(GladeUtil.current_style(stone), 1, 4)
	_check(q_gap > 0.01,
			"mass_quoin: the panel fill does not stop short (%.3f) and grows into its own quoin" % q_gap)
	_check(absf(q_gap - m_gap) < 0.001,
			"mass_quoin: the inset is %.3f where masonry uses %.3f" % [q_gap, m_gap])
	# ...and it is visible in the geometry, not only in the arithmetic: the outer skin has to end
	# short of the corner by that much.
	var reach := _quoin_reach(dressed, "front")
	_check(absf((3.0 - reach) - q_gap) < 0.02,
			"mass_quoin: the skin reaches %.3f of a 3.0 m half-face, which is %.3f short, not %.3f"
					% [reach, 3.0 - reach, q_gap])

	# AN OBLIQUE EDGE STILL DECLINES. A twenty-sided tower turns 18 degrees per joint and reads as
	# curved; quoining those would put a pilaster every 30 cm round a cylinder.
	var round_tower := _quoin_mass(panel, Vector3(260, 0, 0))
	round_tower.shape = GladeMass.Shape.PRISM
	round_tower.sides = 20
	round_tower.style_quoin = stone
	root.add_child(round_tower)
	round_tower.rebuild()
	await process_frame
	_check(int((round_tower.stats as Dictionary).get("quoins", 0)) == 0,
			"mass_quoin: a twenty-sided prism grew %s quoins — an 18 degree turn is not a corner"
					% (round_tower.stats as Dictionary).get("quoins", 0))
	_done("mass_quoin")


## A CHAMFER AT AN ARRIS THAT HAS NO QUOIN — the cheap answer to a razor corner.
##
## Two quads against a quoin's twelve stones, and `GladeBrickMesh` already argues why either is worth
## having: a bevel "catches a highlight along the arris and reads as a dressed stone". Every PIECE in
## the kit had one; the mass's own corners did not.
##
## THE INSET IS THE HALF THAT BITES, exactly as it was for the quoin. A face that ends in a chamfer
## and does not stop short for it overlaps the chamfer, and a corner that z-fights reads as the razor
## it was meant to replace.
func _mass_bevel_suite() -> void:
	var panel: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")
	var stone: GladeStyle = load("res://addons/gladekit/styles/crypt_stone.tres")
	const B := 0.06

	# CONTROL FIRST: no bevel is the mass everyone already had.
	var plain := _quoin_mass(panel, Vector3(300, 0, 0))
	root.add_child(plain)
	plain.rebuild()
	await process_frame
	var plain_stats := (plain.stats as Dictionary).duplicate()
	_check(int(plain_stats.get("bevels", 0)) == 0,
			"mass_bevel CONTROL: an unbevelled mass grew %s chamfers" % plain_stats.get("bevels", 0))

	# FOUR CORNERS, FOUR CHAMFERS.
	var cut := _quoin_mass(panel, Vector3(320, 0, 0))
	cut.bevel = B
	root.add_child(cut)
	cut.rebuild()
	await process_frame
	_check(int((cut.stats as Dictionary).get("bevels", 0)) == 4,
			"mass_bevel: a box grew %s chamfers, not 4" % (cut.stats as Dictionary).get("bevels", 0))
	_check(int((cut.stats as Dictionary).get("bricks", 0))
			== int(plain_stats.get("bricks", 0)),
			"mass_bevel: the face count changed — a chamfer is an extra surface, not a different wall")

	# ...AND THE FACES STOP SHORT FOR THEM, measured off the geometry rather than off the arithmetic.
	# A 6 m face reaches 3.0 from the middle when it runs to the corner, and 2.94 when it does not.
	var reach := _quoin_reach(cut, "front")
	_check(absf((3.0 - reach) - B) < 0.005,
			"mass_bevel: the skin reaches %.3f, which is %.3f short of the corner, not %.3f"
					% [reach, 3.0 - reach, B])

	# A QUOINED CORNER GROWS NO CHAMFER: the quoin owns the arris.
	var both := _quoin_mass(panel, Vector3(340, 0, 0))
	both.bevel = B
	both.style_quoin = stone
	root.add_child(both)
	both.rebuild()
	await process_frame
	_check(int((both.stats as Dictionary).get("bevels", 0)) == 0,
			"mass_bevel: %s chamfers on a quoined mass — a stone standing in a chamfer"
					% (both.stats as Dictionary).get("bevels", 0))
	_check(int((both.stats as Dictionary).get("quoins", 0)) > 0,
			"mass_bevel: the quoins went away when a bevel was asked for")

	# AN EIGHT-SIDED PRISM HAS EIGHT ARRISES, and its 45 degree turns are corners.
	var oct := _quoin_mass(panel, Vector3(360, 0, 0))
	oct.shape = GladeMass.Shape.PRISM
	oct.sides = 8
	oct.bevel = B
	root.add_child(oct)
	oct.rebuild()
	await process_frame
	_check(int((oct.stats as Dictionary).get("bevels", 0)) == 8,
			"mass_bevel: an octagon grew %s chamfers, not 8"
					% (oct.stats as Dictionary).get("bevels", 0))
	_done("mass_bevel")


func _quoin_mass(st: GladeStyle, at: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.style = st
	m.size = Vector3(6, 3, 6)
	m.position = at
	m.hollow = true
	m.rng_seed = 7
	return m


## How far along a face's half-width its outer skin actually reaches, measured from the middle.
func _quoin_reach(m: GladeMass, key: String) -> float:
	var best := 0.0
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if String(m._face_by_mesh.get(mi.name, "")) != key:
			continue
		for v: Vector3 in _tri_verts(mi.mesh, 0):
			best = maxf(best, absf(v.x))
	return best


## Does this mass currently build any surface of the given layer — ".top", ".inner", ".soffit"?
func _mass_has_layer(m: GladeMass, layer: String) -> bool:
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if String(m._face_by_mesh.get(mi.name, "")).ends_with(layer):
			return true
	return false


func _mass_body(m: GladeMass) -> StaticBody3D:
	for c in m.get_children(true):
		if c is StaticBody3D and not (c as Node).is_queued_for_deletion():
			return c
	return null


## Is this world point inside one of the body's boxes? Asked in each shape's own space, so a rotated
## wall answers about the slab it actually is.
func _shape_covers(body: StaticBody3D, world: Vector3) -> bool:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var l: Vector3 = cs.global_transform.affine_inverse() * world
		if absf(l.x) <= box.size.x * 0.5 and absf(l.y) <= box.size.y * 0.5 \
				and absf(l.z) <= box.size.z * 0.5:
			return true
	return false


func _merge_mass(st: GladeStyle, at: Vector3, sz: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.style = st
	m.size = sz
	m.position = at
	m.hollow = true
	return m


## Every vertex a mass currently has, in WORLD space, ignoring generations queued for deletion.
func _merge_verts(m: GladeMass) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		for v: Vector3 in _tri_verts(mi.mesh, 0):
			out.append(m.to_global(v))
	return out


## A mass's deck, as triangles in world XZ. A floor is laid flat, so its PLAN is its geometry and the
## question "is this spot floored" is a point-in-triangle in two dimensions.
##
## THE DECK, NOT THE UNDERSIDE. Both carry the face id "floor" — deliberately, so a mass takes one
## floor material and not two — and they weld into one mesh, so the room you stand in and the face
## the block sits on are told apart only by height. Counting both reports every square metre of every
## house as floored twice.
func _merge_floor_tris(m: GladeMass) -> Array:
	var out: Array = []
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		if not String(m._face_by_mesh.get(mi.name, "")).begins_with("floor"):
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var order: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			order = arrays[Mesh.ARRAY_INDEX]
		else:
			for k in verts.size():
				order.append(k)
		var deck_y: float = m.global_position.y + GladeMass.FLOOR_SLAB * 0.5
		for k in range(0, order.size() - 2, 3):
			var t := PackedVector2Array()
			var high := true
			for j in 3:
				var w: Vector3 = m.to_global(verts[order[k + j]])
				high = high and w.y > deck_y
				t.append(Vector2(w.x, w.z))
			if high:
				out.append(t)
	return out


func _merge_floored(tris: Array, p: Vector2) -> int:
	var n := 0
	for t: PackedVector2Array in tris:
		if Geometry2D.point_is_inside_triangle(p, t[0], t[1], t[2]):
			n += 1
	return n


## STRICTLY inside — inside by a margin in every direction, not merely over the line.
##
## A merged join leaves a great deal of surface lying exactly ON the shared boundary: that is what a
## join IS. Nudging a boundary vertex toward the neighbour's middle therefore reports the seam itself
## as a defect, which is how this test first "found" thirty. What must never happen is a wall
## standing out in the OPEN MIDDLE of the other box, and that is a point buried on all six sides.
const MERGE_MARGIN := 0.3


func _merge_strictly_inside(vols: Array, world: Vector3) -> bool:
	for d: Vector3 in [Vector3.ZERO,
			Vector3(MERGE_MARGIN, 0, 0), Vector3(-MERGE_MARGIN, 0, 0),
			Vector3(0, 0, MERGE_MARGIN), Vector3(0, 0, -MERGE_MARGIN)]:
		if not _merge_in_any(vols, world + d):
			return false
	return true


func _merge_in_any(vols: Array, world: Vector3) -> bool:
	for vol: GladeVolume in vols:
		if vol.contains(world):
			return true
	return false


## Vertices of `who` that stand inside `other` — ASKED ABOUT THE LAYER EACH SURFACE MEETS.
##
## Not one invariant but two, and the difference is the whole point of `GladeClaim.Layer`. An outer
## skin inside the neighbour's BOX is a wall standing in the open middle of another room. A lining
## inside the neighbour's box is normal and required: the two wall bands are one piece of wall where
## they cross, so this one runs on over the neighbour's band and stops at its ROOM. Test both against
## the box and the correct building fails; test both against the room and a real intrusion passes.
##
## Nudged toward the middle first, so a surface lying exactly ON the shared boundary — which is most
## of a merged join — is not counted as buried.
func _merge_inside(who: GladeMass, other: GladeMass) -> int:
	var box := other.junction_volumes()
	var room := other.room_volumes()
	var n := 0
	for c in who.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		var key := String(who._face_by_mesh.get(mi.name, ""))
		if key.begins_with("floor"):
			continue                           # a floor is one polygon; see the note at the caller
		var vols := box
		if (key.ends_with(".inner") or key.ends_with(".top") or key.ends_with(".soffit")) 				and not room.is_empty():
			vols = room
		for v: Vector3 in _tri_verts(mi.mesh, 0):
			var w: Vector3 = who.to_global(v)
			if _merge_strictly_inside(vols, w):
				n += 1
	return n


func _prism(st: GladeStyle, n: int) -> GladeMass:
	var m := GladeMass.new()
	m.size = MASS_SIZE
	m.shape = GladeMass.Shape.PRISM
	m.sides = n
	m.style = st
	root.add_child(m)
	return m


## A HOLE HAS SIDES — and until this cycle a PANEL wall's did not, a floor could not have one at all,
## and a block too thick to bore through refused the opening outright.
##
## THE INVARIANT IS THAT THE SURFACE IS CLOSED. Counting quads proves the code ran; counting EDGES
## proves the result is a hole rather than a gap. Every edge of a watertight surface is shared by
## exactly two triangles, so an edge used an ODD number of times is a place you can see through — and
## that is precisely the bug this cycle exists to fix, stated as a number instead of as a screenshot.
func _reveal_suite() -> void:
	var panel: GladeStyle = load("res://addons/gladekit/styles/panel_stone.tres")

	# A PANEL WALL'S WINDOW: four sides. Its door: three, because a threshold lying in the ground
	# plane z-fights the terrain into a fringe across the doorway.
	# THE FIXTURES RUN OUT ALONG Z, not X. Every other suite spaces its walls along X, and this one
	# measures an arc offset in the wall's own space — where X IS the run — so a wall standing at
	# x = 600 puts its own hole at arc 600-and-something. Spacing on the other axis keeps the two
	# meanings apart.
	var win := _reveal_wall(0.9, Vector3(0, 0, 600))
	_check(int((win.stats as Dictionary).get("lining", 0)) == 8,
			"reveal: a PANEL window grew %s reveal triangles, not 8 (four quads)"
					% (win.stats as Dictionary).get("lining", 0))
	# ...AND THE HOLE IS CLOSED. Asked of the hole's neighbourhood, not of the whole wall: a
	# free-standing wall is not a closed solid — its top, its foot and its two ends are silhouette
	# edges used exactly once by design, and counting those would swamp the thing being measured.
	# Around the opening there is no such excuse, and before this cycle every rim edge there was one.
	# ...AND IT REACHES ALL THE WAY THROUGH, which is what "the hole has sides" means on a wall.
	#
	# NOT the edge-parity test the mass cases use, and the reason is worth writing down: a wall's two
	# sheets are cut into bands by `GladeClaimCut` and into arcs by `GladeArcSplit`, so the rim of the
	# hole is several collinear sub-edges where the reveal has one. That is a T-JUNCTION — the two
	# surfaces meet along the same line with no gap between them — and counting edge uses calls it a
	# hole when your eye cannot. The thickness is the thing that was actually wrong before this cycle
	# (there was none), so the thickness is what to measure.
	var thick := _reveal_thickness(win)
	var want_thick: float = (load("res://addons/gladekit/styles/panel_stone.tres") as GladeStyle).depth
	_check(absf(thick - want_thick) < 0.01,
			"reveal: a PANEL window's sides span %.3f m of a %.3f m wall" % [thick, want_thick])

	var door := _reveal_wall(0.0, Vector3(0, 0, 620))
	_check(int((door.stats as Dictionary).get("lining", 0)) == 6,
			"reveal: a PANEL door grew %s triangles, not 6 — a door has a threshold, not a sill"
					% (door.stats as Dictionary).get("lining", 0))

	# AN OPENING LANDS WHERE IT WAS PUT, not on a grid. `clear_rects` cuts at continuous coordinates
	# and this is the assertion that says so: move the marker by a third of a metre and the hole in
	# the geometry moves by a third of a metre.
	# ONE WALL, THE MARKER DRAGGED ALONG IT — which is the thing being claimed, done the way a person
	# would do it. Three walls at three places would have measured three different walls, and any
	# difference between them could be the drag or could be the wall.
	var drag := _reveal_wall(0.9, Vector3(0, 0, 680))
	var marker: GladeOpening = null
	for c in drag.get_children():
		if c is GladeOpening:
			marker = c
	# COMPARED AGAINST THE ARC THE WALL ITSELF COMPUTED, not against `x + 4`. Those are the same
	# number at the origin and they are not out here: `Curve3D.get_closest_offset` bakes to float32,
	# and on a curve standing at z = 680 it answers 2.186 for a point that is 2.300 along it. That is
	# Godot's precision, not the kit's — the hole tracks whatever offset it is given to the
	# millimetre, which is exactly what this is asserting.
	for arc: float in [-1.70, -1.37, 0.44]:
		marker.position = Vector3(arc, 0, 0)
		drag.rebuild()
		var want: float = drag.curve.get_closest_offset(marker.position)
		var span := _reveal_span(drag)
		_check(span.size() == 2 and absf(span[1] - span[0] - 1.2) < 0.02,
				"reveal: a 1.2 m window cut a hole %s wide" % [span])
		_check(span.size() == 2 and absf((span[0] + span[1]) * 0.5 - want) < 0.02,
				"reveal: the marker at arc %.3f cut the wall at %s — a hole that does not follow the "
						% [want, span] + "marker is a hole on a grid")

	# A HOLE IN A CAP, which needs the face named — see `GladeOpening.face`.
	var slab := _hole_mass(panel, Vector3(0, 0, 700), Vector3(4, 0.6, 4), "top",
			GladeOpening.Shape.RECT, 0.0)
	_check(int((slab.stats as Dictionary).get("reveals", 0)) == 8,
			"reveal: a hole through a slab's cap grew %s triangles, not 8"
					% (slab.stats as Dictionary).get("reveals", 0))
	_check(_open_edges(slab) == 0,
			"reveal: a hole in a cap leaves %d edges used once" % _open_edges(slab))

	# ...AND IN AN N-GON CAP, which is the keyhole. Skinning the bounding rectangle instead would
	# floor the whole box, so the assertion is on AREA: an octagon with a hole in it, not a square.
	var oct := _hole_mass(panel, Vector3(0, 0, 720), Vector3(5, 0.6, 5), "side8",
			GladeOpening.Shape.RECT, 0.0, 8)
	_check(_open_edges(oct) == 0,
			"reveal: a hole in an octagonal cap leaves %d edges used once" % _open_edges(oct))
	var cap := _face_area(oct, "side8")
	_check(cap > 0.5 and cap < _octagon_area(2.5) - 0.5,
			"reveal: an octagonal cap with a 1 m hole skinned %.2f m2, against %.2f m2 whole"
					% [cap, _octagon_area(2.5)])

	# A ROUND HOLE. Sixteen facets, so sixteen reveal quads and a sixteen-sided back on the recess —
	# far more than the four a bounding box would have given it.
	var rose := _hole_mass(panel, Vector3(0, 0, 740), Vector3(4, 3, 4), "",
			GladeOpening.Shape.ROUND, 0.0)
	_check(int((rose.stats as Dictionary).get("reveals", 0)) > 30,
			"reveal: a round opening grew only %s triangles — it came out as its bounding box"
					% (rose.stats as Dictionary).get("reveals", 0))
	_check(_open_edges(rose) == 0,
			"reveal: a round opening leaves %d edges used once" % _open_edges(rose))

	# A NICHE HAS A BACK. Both roads are `_reveal`; the difference is one flag, and it is worth
	# pinning because a recess without a back is a hole into the middle of a solid.
	var niche := _hole_mass(panel, Vector3(0, 0, 760), Vector3(4, 3, 4), "",
			GladeOpening.Shape.RECT, 0.5)
	_check(int((niche.stats as Dictionary).get("reveals", 0)) == 10,
			"reveal: a niche grew %s triangles, not 10 — four sides and a back"
					% (niche.stats as Dictionary).get("reveals", 0))
	_check(_open_edges(niche) == 0,
			"reveal: a niche leaves %d edges used once" % _open_edges(niche))
	_check(_deepest_reveal(niche) < 0.56,
			"reveal: a 0.5 m niche runs %.2f m into the block" % _deepest_reveal(niche))
	_done("reveal")


func _reveal_wall(sill: float, at: Vector3, arc := 0.0) -> GladeWall:
	var w := _wall([at + Vector3(-4, 0, 0), at + Vector3(4, 0, 0)], 3.0)
	w.style = load("res://addons/gladekit/styles/panel_stone.tres")
	var o := GladeOpening.new()
	o.width = 1.2
	o.height = 1.6
	o.shape = GladeOpening.Shape.RECT
	o.sill_height = sill
	o.position = Vector3(arc, 0, 0)
	w.add_child(o)
	w.rebuild()
	return w


func _hole_mass(st: GladeStyle, at: Vector3, size: Vector3, face: String, shape: int,
		depth: float, sides := 0) -> GladeMass:
	var m := GladeMass.new()
	m.size = size
	m.position = at
	m.style = st
	m.rng_seed = 5
	m.generate_collision = false
	if sides > 0:
		m.shape = GladeMass.Shape.PRISM
		m.sides = sides
	var o := GladeOpening.new()
	o.width = 1.0
	o.height = 1.0
	o.shape = shape
	o.face = face
	o.depth = depth
	o.sill_height = 0.0
	# On a named horizontal face the marker says WHERE; on a wall it says how far along and how high.
	o.position = Vector3(0.4, size.y, 0.2) if not face.is_empty() \
			else Vector3(0.0, size.y * 0.4, -size.z * 0.5)
	m.add_child(o)
	root.add_child(m)
	m.rebuild()
	return m


## Edges used an ODD number of times across every ArrayMesh under `n` — the count of places you can
## see through. Welded on position to a tenth of a millimetre, because the surfaces are committed by
## separate `SurfaceTool` runs and share no vertex identity.
##
## MEASURED IN THE NODE'S OWN SPACE, and that is not tidiness. The fixtures in this file stand
## hundreds of metres out along X to keep out of each other's claims, and a float32 at x = 700 has a
## spacing of 6e-5 — coarser than the 1e-4 this welds at. Two vertices that ARE the same corner
## rounded to different keys, and every seam in the building read as a hole.
func _open_edges(n: Node3D) -> int:
	return _open_edges_near(n, Vector3.INF, 0.0)


## The same count, restricted to edges whose midpoint is within `radius` of `centre` in world space.
## `centre = Vector3.INF` means the whole node.
func _open_edges_near(n: Node3D, centre: Vector3, radius: float) -> int:
	var edges := {}
	for c in n.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() \
				or not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			var v: PackedVector3Array = _tri_verts(mi.mesh, s)
			var t := 0
			while t + 2 < v.size():
				for e: Array in [[t, t + 1], [t + 1, t + 2], [t + 2, t]]:
					var a := v[e[0]]
					var b := v[e[1]]
					if centre != Vector3.INF and ((a + b) * 0.5).distance_to(centre) > radius:
						continue
					var k := _edge_key(n.to_local(a), n.to_local(b))
					edges[k] = int(edges.get(k, 0)) + 1
				t += 3
	var odd := 0
	for k: Variant in edges:
		if int(edges[k]) % 2 == 1:
			odd += 1
	return odd


## WELDED AT A MILLIMETRE, not at a tenth of one. The rim of a hole is computed twice by two
## different roads — `GladePolygon` lifts it out of a 2-D clip, `GladeReveal` builds it straight in
## 3-D — and a float32 round trip through the 2-D frame moves it by more than 1e-4. A millimetre is
## still two orders below anything visible, and it is the difference between measuring the geometry
## and measuring the arithmetic that produced it.
static func _edge_key(a: Vector3, b: Vector3) -> String:
	var p := "%.3f,%.3f,%.3f" % [a.x, a.y, a.z]
	var q := "%.3f,%.3f,%.3f" % [b.x, b.y, b.z]
	return p + "|" + q if p < q else q + "|" + p


## The skinned area of one named face, in square metres — how a face with a hole in it is told from a
## bounding rectangle that swallowed the whole outline.
func _face_area(m: GladeMass, key: String) -> float:
	var area := 0.0
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() \
				or not (mi.mesh is ArrayMesh):
			continue
		if String(m._face_by_mesh.get(mi.name, "")) != key:
			continue
		for s in mi.mesh.get_surface_count():
			var v: PackedVector3Array = _tri_verts(mi.mesh, s)
			var t := 0
			while t + 2 < v.size():
				area += (v[t + 1] - v[t]).cross(v[t + 2] - v[t]).length() * 0.5
				t += 3
	return area


static func _octagon_area(r: float) -> float:
	return 2.0 * sqrt(2.0) * r * r


## Where the hole in a PANEL wall actually is, along the run — measured off the reveal quads, which
## are the only geometry standing across the wall's thickness rather than along its face.
##
## Named apart from `_hole_span` above, which asks the same question of MASONRY by probing for
## missing stones. A panel has no stones to miss, so the two cannot share an implementation.
func _reveal_span(w: GladeWall) -> Array:
	var lo := INF
	var hi := -INF
	for c in w.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() \
				or not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				if ns.size() <= i or absf(ns[i].z) > 0.5:
					continue                   # a face of the wall, not a side of the hole
				var x := w.to_local(vs[i]).x + 4.0
				lo = minf(lo, x)
				hi = maxf(hi, x)
	return [] if lo > hi else [lo, hi]


## MODULES — the handcraft socket at wall scale, and the two things it must never do: leave a gap,
## and snap an opening to its grid.
##
## A modular kit's whole failure mode is visible seams, so the assertions here are about arithmetic
## rather than about looks: the bays must EXACTLY cover the run with no overlap and no remainder, no
## bay may be stretched past what the style allows, and the module carrying the door must stand where
## the marker is rather than at the nearest grid line — which is the objection the mode was weighed
## against in the first place.
func _module_suite() -> void:
	const LEN := 10.0
	const H := 2.8
	var st := GladeStyle.new()
	st.wall_mode = GladeStyle.WallMode.MODULE
	st.module_size = Vector3(1.2, H, 0.34)
	st.module_stretch = 1.25
	st.depth = 0.34

	# --- a plain run: whole modules, exactly covering it ----------------------------------------
	var plain := _module_wall(st, Vector3(0, 0, 900), [])
	var bays := _bays_of(plain, H)
	_check(not bays.is_empty(), "module: a %d m wall grew no modules at all" % int(LEN))
	_check(absf(_span_of(bays) - LEN) < 0.01,
			"module: %d bays cover %.3f m of a %.1f m wall" % [bays.size(), _span_of(bays), LEN])
	_check(_max_overlap(bays) < 0.005,
			"module: two bays overlap by %.3f m" % _max_overlap(bays))
	for b: Dictionary in bays:
		var ratio: float = float(b.w) / st.module_size.x
		_check(maxf(ratio, 1.0 / ratio) <= st.module_stretch + 0.001,
				"module: a bay is %.3f m against a %.2f m module — %.2fx, past the %.2f limit"
						% [b.w, st.module_size.x, maxf(ratio, 1.0 / ratio), st.module_stretch])

	# --- an opening takes a bay of its own, AT the marker ---------------------------------------
	# The width is deliberately not a multiple of the module, and the position deliberately not on a
	# grid line: if either were, a snapping implementation would pass by luck.
	for arc: float in [2.15, 4.37, 6.9]:
		var w := _module_wall(st, Vector3(0, 0, 920 + arc * 10.0), [{"at": arc, "sill": 0.0,
				"w": 1.1}])
		var doors := _bays_of(w, H, GladeFillModule.SLOT_DOOR)
		_check(doors.size() == 1, "module: a door opening grew %d door modules, not 1" % doors.size())
		if doors.size() == 1:
			var want: float = w.curve.get_closest_offset(Vector3(arc - LEN * 0.5, 0, 0))
			_check(absf(float(doors[0].mid) - want) < 0.02,
					"module: a door asked for at arc %.2f put its module at %.2f — a module that "
							% [want, doors[0].mid] + "snaps to a grid is the thing this mode is for")
			_check(absf(float(doors[0].w) - 1.1) < 0.02,
					"module: a 1.10 m door got a %.2f m module" % doors[0].w)
		# ...and the run is still exactly covered, which is what breaking it at the opening is FOR.
		var all := _bays_of(w, H)
		_check(absf(_span_of(all) - LEN) < 0.02,
				"module: with an opening at %.2f the bays cover %.3f m of %.1f"
						% [arc, _span_of(all), LEN])

	# --- a window is a window and a door is a door, told apart by the sill ----------------------
	var mixed := _module_wall(st, Vector3(0, 0, 990), [{"at": 3.0, "sill": 0.0, "w": 1.2},
			{"at": 7.0, "sill": 1.0, "w": 1.2}])
	_check(_bays_of(mixed, H, GladeFillModule.SLOT_DOOR).size() == 1
			and _bays_of(mixed, H, GladeFillModule.SLOT_WINDOW).size() == 1,
			"module: a door and a window did not pick one variant each")

	# --- AN EMPTY SOCKET FALLS BACK. With a wall module and no window module, the opening keeps a
	# plain panel and is simply not expressed — the degradation every socket in this kit makes.
	var partial := GladeStyle.new()
	partial.wall_mode = GladeStyle.WallMode.MODULE
	partial.module_size = st.module_size
	partial.depth = st.depth
	partial.module_wall = BoxMesh.new()
	var fell := _module_wall(partial, Vector3(0, 0, 1010), [{"at": 5.0, "sill": 1.0, "w": 1.2}])
	_check(_bays_of(fell, H, GladeFillModule.SLOT_WINDOW).is_empty(),
			"module: an empty module_window socket still asked for slot 1 — an empty socket must "
					+ "fall back, not leave a hole")
	_check(absf(_span_of(_bays_of(fell, H)) - LEN) < 0.02,
			"module: falling back left a gap in the run")

	# --- AND THE SOCKET IS WIRED ON A MASS AT ALL, which nothing has ever checked. `GladeWall` and
	# `GladeRoof` have always honoured `brick_meshes`; `GladeMass` counted them and then committed
	# the procedural box for every slot, so hand-authored geometry could not reach it.
	var mine := BoxMesh.new()
	var stone := (load("res://addons/gladekit/styles/crypt_stone.tres") as GladeStyle).duplicate()
	stone.brick_meshes = [mine] as Array[Mesh]
	var m := GladeMass.new()
	m.size = Vector3(3, 2.4, 3)
	m.position = Vector3(0, 0, 1030)
	m.style = stone
	m.generate_collision = false
	root.add_child(m)
	m.rebuild()
	var used := false
	for c in m.get_children(true):
		var mmi := c as MultiMeshInstance3D
		if mmi and mmi.multimesh and mmi.multimesh.mesh == mine:
			used = true
	_check(used, "module: a mass ignored style.brick_meshes — the handcraft socket is unwired on "
			+ "the one node whose premise is that it PLACES pieces")
	_done("module")


## THE ROLE TABLE — that a kit of N named blocks numbers its slots the way it says it does.
##
## The three sockets were the whole of MODULE mode until `ProcKitSet`; this suite exists because
## an ordered list whose INDEX is a MultiMesh identity is a thing that can rot silently.
func _module_role_suite() -> void:
	var kit := _kit([&"wall", &"window", &"door", &"bay", &"vent"])
	var st := GladeStyle.new()
	st.wall_mode = GladeStyle.WallMode.MODULE
	st.module_set = kit
	st.module_size = Vector3(1.2, 2.8, 0.34)
	st.depth = 0.34

	_check(GladeFillModule.slot_count(st) == 5,
			"module_role: a 5-role kit reported %d slots" % GladeFillModule.slot_count(st))
	for i in 5:
		var want: StringName = kit.roles[i].role_name
		_check(GladeFillModule.slot_named(st, want) == i,
				"module_role: role \"%s\" is at index %d but slot_named said %d — the index IS the "
						% [want, i, GladeFillModule.slot_named(st, want)]
						+ "MultiMesh, so this drifting is a silent scene-wide reslot")
		_check(GladeFillModule.mesh_for(st, i) != null,
				"module_role: slot %d resolved to no mesh at all; every socket must degrade to the "
						% i + "procedural set rather than to nothing")
	_check(GladeFillModule.slot_named(st, &"portcullis") == -1,
			"module_role: a name the kit has not got must answer -1, not a slot")

	# THE LEGACY PIN. This is the assertion that keeps every MODULE wall already in a scene building
	# what it built before sets existed: no set means exactly wall/window/door at 0/1/2.
	var old := GladeStyle.new()
	old.wall_mode = GladeStyle.WallMode.MODULE
	old.module_size = Vector3(1.2, 2.8, 0.34)
	_check(GladeFillModule.slot_count(old) == GladeFillModule.SLOTS,
			"module_role: a style with no module_set reported %d slots, not the legacy %d"
					% [GladeFillModule.slot_count(old), GladeFillModule.SLOTS])
	_check(GladeFillModule.slot_named(old, &"wall") == GladeFillModule.SLOT_WALL
			and GladeFillModule.slot_named(old, &"window") == GladeFillModule.SLOT_WINDOW
			and GladeFillModule.slot_named(old, &"door") == GladeFillModule.SLOT_DOOR,
			"module_role: the synthesized legacy kit is not wall/window/door at 0/1/2")

	# ROLE ORDER SURVIVES THE DISK. The whole design rests on a saved kit numbering its slots the
	# same way after a reload; asserting it here makes that claim falsifiable rather than assumed.
	var path := "user://ashgrove_kit_roundtrip.tres"
	if ResourceSaver.save(kit, path) == OK:
		var back := load(path) as ProcKitSet
		_check(back != null and back.roles.size() == 5, "module_role: a saved kit did not load back")
		if back != null and back.roles.size() == 5:
			var same := true
			for i in 5:
				if back.roles[i].role_name != kit.roles[i].role_name or back.index_of(
						kit.roles[i].role_name) != i:
					same = false
			_check(same, "module_role: role ORDER did not survive a save/load round trip")
	_done("module_role")


## AN OPENING THAT NAMES ITS BLOCK, and what happens when it names one that is not there.
func _module_named_suite() -> void:
	const H := 2.8
	var st := GladeStyle.new()
	st.wall_mode = GladeStyle.WallMode.MODULE
	st.module_set = _kit([&"wall", &"window", &"door", &"bay", &"vent"])
	st.module_size = Vector3(1.2, H, 0.34)
	st.depth = 0.34

	# All three sills are 1.0, so the AUTOMATIC rule would call every one of them a window. Anything
	# that lands elsewhere got there by being asked for by name.
	var w := _module_wall(st, Vector3(0, 0, 1200), [
		{"at": 2.0, "sill": 1.0, "w": 1.2, "module": &"bay"},
		{"at": 5.0, "sill": 1.0, "w": 1.2, "module": &"vent"},
		{"at": 8.0, "sill": 1.0, "w": 1.2, "module": &""}])
	_check(_bays_of(w, H, GladeFillModule.slot_named(st, &"bay")).size() == 1,
			"module_named: an opening asking for \"bay\" did not get the bay block")
	_check(_bays_of(w, H, GladeFillModule.slot_named(st, &"vent")).size() == 1,
			"module_named: an opening asking for \"vent\" did not get the vent block")
	_check(_bays_of(w, H, GladeFillModule.slot_named(st, &"window")).size() == 1,
			"module_named: an unnamed opening stopped falling through to the sill rule")

	# A NAME THE KIT HAS NOT GOT IS NOT AN ERROR. A building must stand while its kit is still
	# arriving, so an unknown role falls through to auto and leaves the run exactly covered.
	var unknown := _module_wall(st, Vector3(0, 0, 1230), [
		{"at": 5.0, "sill": 1.0, "w": 1.2, "module": &"nosuchblock"}])
	_check(_bays_of(unknown, H, GladeFillModule.slot_named(st, &"window")).size() == 1,
			"module_named: an unknown role must fall through to auto, not vanish")
	_check(absf(_span_of(_bays_of(unknown, H)) - 10.0) < 0.02,
			"module_named: an unknown role left a %.3f m gap in a 10 m run"
					% (10.0 - _span_of(_bays_of(unknown, H))))
	_done("module_named")


## THE FIT POLICY — that an authored block is not stretched to whatever width the marker happened
## to be. This is the defect the Ashgrove bay windows found.
func _module_fit_suite() -> void:
	const H := 2.8
	# STRETCH first, and it must still stretch: that is what every module did before Fit existed,
	# and the legacy kit has no per-role size to do anything else with.
	var s_st := GladeStyle.new()
	s_st.wall_mode = GladeStyle.WallMode.MODULE
	s_st.module_set = _kit([&"wall", &"window"], 1.2, ProcKitRole.Fit.STRETCH)
	s_st.module_size = Vector3(1.2, H, 0.34)
	s_st.depth = 0.34
	var wide := _module_wall(s_st, Vector3(0, 0, 1260), [{"at": 5.0, "sill": 1.0, "w": 3.6}])
	var sb := _bays_of(wide, H, GladeFillModule.slot_named(s_st, &"window"))
	_check(sb.size() == 1 and absf(float(sb[0].w) - 3.6) < 0.02,
			"module_fit: STRETCH must fill the marker — a 3.6 m marker gave a %.2f m module"
					% (float(sb[0].w) if sb.size() == 1 else -1.0))

	# ASPECT: the same marker, the same authored block, and now the block keeps its own width and
	# the remainder becomes wall.
	var a_st := GladeStyle.new()
	a_st.wall_mode = GladeStyle.WallMode.MODULE
	a_st.module_set = _kit([&"wall", &"window"], 1.2, ProcKitRole.Fit.ASPECT)
	a_st.module_size = Vector3(1.2, H, 0.34)
	a_st.depth = 0.34
	var kept := _module_wall(a_st, Vector3(0, 0, 1290), [{"at": 5.0, "sill": 1.0, "w": 3.6}])
	var ab := _bays_of(kept, H, GladeFillModule.slot_named(a_st, &"window"))
	_check(ab.size() == 1 and absf(float(ab[0].w) - 1.2) < 0.02,
			"module_fit: ASPECT must keep the authored 1.20 m — got %.2f m, which is the artist's "
					% (float(ab[0].w) if ab.size() == 1 else -1.0)
					+ "mouldings stretched threefold")
	var all := _bays_of(kept, H)
	_check(absf(_span_of(all) - 10.0) < 0.02,
			"module_fit: ASPECT left %.3f m of the run uncovered" % (10.0 - _span_of(all)))
	_check(_max_overlap(all) < 0.005,
			"module_fit: ASPECT overlapped two bays by %.3f m" % _max_overlap(all))

	# A SLIVER IS FOLDED IN, not left standing. A 1.25 m marker against a 1.2 m block leaves 2.5 cm
	# each side, which is a crack with a mesh in it rather than a pier.
	var tight := _module_wall(a_st, Vector3(0, 0, 1320), [{"at": 5.0, "sill": 1.0, "w": 1.25}])
	var tb := _bays_of(tight, H, GladeFillModule.slot_named(a_st, &"window"))
	_check(tb.size() == 1 and absf(float(tb[0].w) - 1.25) < 0.02,
			"module_fit: a sub-MIN_BAY remainder must be folded into the module, not left as a sliver")
	_check(absf(_span_of(_bays_of(tight, H)) - 10.0) < 0.02,
			"module_fit: folding a sliver broke the exact cover")
	_done("module_fit")


## THE CRUX — a solid whose faces wear DIFFERENT kits must draw each face with its own blocks.
##
## This fails against the code before `ProcKitSlotPlan`: the mass sized one buffer for the whole
## solid and resolved every slot through `_piece_style()`, so the second kit was drawn with the
## first kit's meshes. Silently — no error, no warning, the wrong wall.
func _mass_module_suite() -> void:
	var front_mesh := BoxMesh.new()
	var side_mesh := SphereMesh.new()
	var a := GladeStyle.new()
	a.wall_mode = GladeStyle.WallMode.MODULE
	a.module_set = _kit([&"wall", &"window", &"door", &"bay", &"vent"], 1.2,
			ProcKitRole.Fit.STRETCH, front_mesh)
	a.module_size = Vector3(1.2, 2.6, 0.3)
	a.depth = 0.3
	# DELIBERATELY A DIFFERENT LENGTH: five roles against two. Equal-length kits would pass by luck
	# even with one shared numbering.
	var b := GladeStyle.new()
	b.wall_mode = GladeStyle.WallMode.MODULE
	b.module_set = _kit([&"wall", &"window"], 1.2, ProcKitRole.Fit.STRETCH, side_mesh)
	b.module_size = Vector3(1.2, 2.6, 0.3)
	b.depth = 0.3

	var m := GladeMass.new()
	m.size = Vector3(6, 2.6, 6)
	m.position = Vector3(0, 0, 1400)
	m.style = b
	m.style_front = a
	m.style_left = b
	m.style_right = b
	m.style_back = b
	m.generate_collision = false
	root.add_child(m)
	m.rebuild()
	await process_frame

	var saw_front := 0
	var saw_side := 0
	for c in m.get_children(true):
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if mmi.multimesh.mesh == front_mesh:
			saw_front += mmi.multimesh.instance_count
		elif mmi.multimesh.mesh == side_mesh:
			saw_side += mmi.multimesh.instance_count
	_check(saw_front > 0, "mass_module: the front face's kit drew nothing — its blocks were "
			+ "substituted with another face's, which is the bug ProcKitSlotPlan exists to fix")
	_check(saw_side > 0, "mass_module: the side faces' kit drew nothing")
	# SEVEN SLOTS, NOT FIVE. Two kits of 5 and 2 need 7 between them; sharing one numbering would
	# report 5 and quietly overlay one kit on the other.
	_check(int(m.stats.get("variants", 0)) == 7,
			"mass_module: a 5-role kit and a 2-role kit on one solid want 7 slots, got %d"
					% int(m.stats.get("variants", 0)))
	_done("mass_module")


## A kit of N roles, all sharing one mesh (or none, to exercise the procedural fallback).
func _kit(names: Array, w := 1.2, fit := ProcKitRole.Fit.STRETCH,
		mesh: Mesh = null) -> ProcKitSet:
	var k := ProcKitSet.new()
	var roles: Array[ProcKitRole] = []
	for n: StringName in names:
		var r := ProcKitRole.new()
		r.role_name = n
		r.source = mesh if mesh != null else BoxMesh.new()
		r.size = Vector3(w, 2.8, 0.34)
		# The WALL role always stretches: it is the grid, and an aspect-locked grid cannot close a run.
		r.fit = ProcKitRole.Fit.STRETCH if n == &"wall" else fit
		roles.append(r)
	k.roles = roles
	return k


func _module_wall(st: GladeStyle, at: Vector3, holes: Array) -> GladeWall:
	var w := _wall([at + Vector3(-5, 0, 0), at + Vector3(5, 0, 0)], 2.8)
	w.style = st
	for h: Dictionary in holes:
		var o := GladeOpening.new()
		o.width = float(h.w)
		o.height = 2.0 if float(h.sill) < 0.4 else 1.2
		o.shape = GladeOpening.Shape.RECT
		o.sill_height = float(h.sill)
		o.module = StringName(h.get("module", &""))
		o.position = Vector3(float(h.at) - 5.0, 0, 0)
		w.add_child(o)
	w.rebuild()
	return w


## The bays a MODULE fill laid, as `{mid, w}` in arc coordinates, sorted along the run.
##
## Read off the buffer rather than the MultiMesh, for the reason every other suite here does: the
## headless dummy renderer does not retain those buffers. Filtered on HEIGHT, because a corner post
## or a quoin lands in the same slots and is not a module.
func _bays_of(w: GladeWall, height: float, slot := -1) -> Array:
	var buf = w._buf
	var out: Array = []
	if buf == null:
		return out
	for v in buf.xforms.size():
		if slot >= 0 and v != slot:
			continue
		for t: Transform3D in (buf.xforms[v] as Array):
			var s := t.basis.get_scale()
			if absf(s.y - height) > 0.02:
				continue
			out.append({"mid": w.to_local(t.origin).x + 5.0, "w": s.x, "slot": v})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.mid) < float(b.mid))
	return out


static func _span_of(bays: Array) -> float:
	var total := 0.0
	for b: Dictionary in bays:
		total += float(b.w)
	return total


## The worst overlap between two neighbouring bays — zero on a run that is exactly divided.
static func _max_overlap(bays: Array) -> float:
	var worst := 0.0
	for i in range(1, bays.size()):
		var a: Dictionary = bays[i - 1]
		var b: Dictionary = bays[i]
		var gap: float = (float(b.mid) - float(b.w) * 0.5) - (float(a.mid) + float(a.w) * 0.5)
		worst = maxf(worst, -gap)
	return worst


## How far a wall's reveal reaches ACROSS the wall — the distance between its nearest and furthest
## vertex along the wall's own normal. Before this cycle a PANEL wall had no reveal and this was 0.
func _reveal_thickness(w: GladeWall) -> float:
	var lo := INF
	var hi := -INF
	for c in w.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() \
				or not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				if ns.size() <= i or absf(ns[i].z) > 0.5:
					continue                   # a face of the wall, not a side of the hole
				var z := w.to_local(vs[i]).z
				lo = minf(lo, z)
				hi = maxf(hi, z)
	return 0.0 if lo > hi else hi - lo


## How far the deepest reveal vertex stands in from the face it went in at.
func _deepest_reveal(m: GladeMass) -> float:
	var deep := 0.0
	for c in m.get_children(true):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() \
				or not (mi.mesh is ArrayMesh):
			continue
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in _tri_verts(mi.mesh, s):
				var l := m.to_local(v)
				if l.z < -m.size.z * 0.5 + 0.001:
					continue
				deep = maxf(deep, l.z + m.size.z * 0.5)
	return deep
