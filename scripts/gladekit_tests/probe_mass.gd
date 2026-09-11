extends SceneTree
## THE CUBE TEST, as numbers. One `GladeMass`, two styles on two adjacent faces, and the question
## that decides whether volumes are a foundation worth building on: DOES THE ARRIS COME OUT RIGHT?
##
##   Godot_console.exe --headless --path . --script res://scripts/gladekit_tests/probe_mass.gd
##
## TWO CASES, and the pair is the point:
##
##   COMPATIBLE    two styles that share a `course_height`. The beds MUST meet, the quoin must
##                 alternate, and nothing may pass through anything. This is "blends right".
##   INCOMPATIBLE  two styles whose course heights differ (0.30 vs 0.26). The beds CANNOT meet and
##                 no rule can make them — the same fact already measured as a 0.15 m hole at a
##                 storey boundary in roadmap A9, stood up on its end. Run so the failure is a
##                 KNOWN number rather than a surprise.
##
## Prints rather than asserts — this is the instrument you read while the rule is being written.

const STONE := "res://addons/gladekit/styles/crypt_stone.tres"
const ALSACE := "res://addons/gladekit/styles/alsace_stone.tres"

const SIZE := Vector3(4.0, 3.0, 4.0)
const FACE_A := 0                              ## -X
const FACE_B := 4                              ## -Z


func _initialize() -> void:
	_run()


func _run() -> void:
	# The tree's root is not usable during `_initialize()` — a node added before the first frame
	# reports `is_inside_tree() == false`, so its `_ready` never fires and it silently builds
	# nothing. `verify_gladekit.gd` gets away without this only because its suites await.
	await process_frame

	var crypt: GladeStyle = load(STONE)
	# A SECOND STYLE THAT IS GEOMETRICALLY COMPATIBLE: same course height and depth, different
	# colour. That is the case the user's test is actually about — two materials, one coursing.
	var pale: GladeStyle = crypt.duplicate()
	# `palette` is Array[Color] and `palette_weights` is PackedFloat32Array, and they are indexed in
	# lockstep — hand the first a PackedColorArray and the assignment throws inside an awaited
	# function, which unwinds SILENTLY and hangs the run with no output at all. Exactly the trap
	# `verify_gladekit.gd`'s header is about.
	var pale_palette: Array[Color] = [Color(0.80, 0.76, 0.63), Color(0.71, 0.67, 0.55),
			Color(0.86, 0.82, 0.70)]
	pale.palette = pale_palette
	pale.palette_weights = PackedFloat32Array([3, 2, 2])
	var alsace: GladeStyle = load(ALSACE)

	_case("COMPATIBLE  (same course_height)", crypt, pale)
	_case("INCOMPATIBLE (0.300 vs %.3f)" % alsace.course_height, crypt, alsace)

	# THE CONTROL. With the mitre off, the two faces' stones grow into each other and assertion [1]
	# MUST fail. A test whose control passes is testing nothing.
	var no_mitre_a: GladeStyle = crypt.duplicate()
	var no_mitre_b: GladeStyle = pale.duplicate()
	no_mitre_a.corner_mitre = false
	no_mitre_b.corner_mitre = false
	_case("CONTROL — mitre OFF, [1] must FAIL", no_mitre_a, no_mitre_b)

	# ALL FOUR SIDES, alternating, so every face is inset at BOTH ends and all four arrises are cut.
	_all_four(crypt, pale)
	_shapes(crypt)
	_drag(crypt)
	quit(0)


## EVERY BASIC FORM, and the one number that decides whether its edges are corners.
func _shapes(st: GladeStyle) -> void:
	print("\\n=== SHAPES ===")
	for n in [3, 4, 6, 8, 20]:
		var m := GladeMass.new()
		m.size = SIZE
		m.shape = GladeMass.Shape.PRISM
		m.sides = n
		m.style = st
		root.add_child(m)
		m.rebuild()
		var turn := 360.0 / float(n)
		print("  prism %2d sides: faces %s  bricks %4d  quoins %3d   turn %.0f deg vs corner_angle %.0f -> %s"
				% [n, m.stats.get("faces", 0), m.stats.get("bricks", 0), m.stats.get("quoins", 0),
						turn, st.corner_angle_deg,
						"corners" if turn > st.corner_angle_deg else "smooth"])
		m.queue_free()


## THE DRAG VERBS, exercised without a gizmo — which is the whole reason they live on the node.
func _drag(st: GladeStyle) -> void:
	print("\\n=== DRAG ===")
	var m := GladeMass.new()
	m.size = SIZE
	m.style = st
	root.add_child(m)
	m.rebuild()

	# Push the +X face out to local x = 4. The far (-X) face must NOT move.
	var far_before := m.position.x - m.size.x * 0.5
	var ok := m.push_face(1, Vector3(4.0, 0.0, 0.0))
	var far_after := m.position.x - m.size.x * 0.5
	print("  push_face(+X -> 4.0): %s   size.x %.2f -> %.2f   far face %.3f -> %.3f  %s"
			% [ok, SIZE.x, m.size.x, far_before, far_after,
					"OK" if absf(far_before - far_after) < 0.001 else "FAIL - far side moved"])

	# A prism refuses: pushing one side of a regular polygon cannot be stored.
	m.shape = GladeMass.Shape.PRISM
	print("  push_face on a PRISM: %s   %s"
			% [m.push_face(1, Vector3(4, 0, 0)), "OK (refused)" if not m.push_face(1, Vector3(4, 0, 0)) else "FAIL"])
	m.shape = GladeMass.Shape.BOX

	# The height pearl lands on whole courses.
	m.set_solid_height(3.44)
	# Compared against the nearest whole number of courses rather than with `fmod`, which on
	# 3.30 / 0.30 returns 0.2999998 and fails a test the code passed.
	var courses := roundf(m.size.y / st.course_height)
	print("  set_solid_height(3.44) with course %.2f -> %.2f (= %d courses)   %s"
			% [st.course_height, m.size.y, int(courses),
					"OK" if absf(m.size.y - courses * st.course_height) < 0.001
							else "FAIL - not a whole course"])

	# SCALING MUST NOT STRETCH STONES. The bake absorbs it into `size` and regrows.
	var before := m.size
	m.scale = Vector3(2.0, 1.0, 1.0)
	m._bake_scale()
	print("  scale x2 baked: size.x %.2f -> %.2f, scale back to %s   %s"
			% [before.x, m.size.x, m.scale,
					"OK" if is_equal_approx(m.size.x, before.x * 2.0) and m.scale.is_equal_approx(Vector3.ONE)
							else "FAIL"])
	m.queue_free()


func _case(label: String, a: GladeStyle, b: GladeStyle) -> void:
	print("\n=== %s ===" % label)
	print("  A course=%.3f depth=%.3f   B course=%.3f depth=%.3f"
			% [a.course_height, a.depth, b.course_height, b.depth])

	var m := GladeMass.new()
	m.size = SIZE
	m.style_left = a                               # face 0, -X
	m.style_front = b                              # face 4, -Z
	root.add_child(m)
	m.rebuild()

	var xf := m.snap_transforms
	print("  stats: %s" % [m.stats])
	if xf.is_empty():
		print("  FAIL — nothing was built")
		m.queue_free()
		return

	# Where the two centrelines cross: the exact spot a quoin is centred on. Classifying by this
	# rather than by "near both planes" is what separates 10 quoins from the 33 face stones that
	# merely stand near the corner.
	var h := SIZE * 0.5
	var cx := -h.x + a.depth * 0.5
	var cz := -h.z + b.depth * 0.5
	var on_a: Array[Transform3D] = []
	var on_b: Array[Transform3D] = []
	var quoin: Array[Transform3D] = []
	for t: Transform3D in xf:
		var p := t.origin
		if absf(p.x - cx) < 0.06 and absf(p.z - cz) < 0.06:
			quoin.append(t)
		elif absf(p.x - cx) < a.depth:
			on_a.append(t)
		elif absf(p.z - cz) < b.depth:
			on_b.append(t)
	print("  pieces %d   face A %d   face B %d   quoins %d"
			% [xf.size(), on_a.size(), on_b.size(), quoin.size()])

	# 1. NO STONE THROUGH STONE — the failure the mitre exists to prevent.
	#
	# ACROSS ALL PAIRS, not across the two classified buckets. Classifying first is what let the
	# control pass: with the mitre off, the face stones grow INTO the corner box, land on the
	# centreline crossing, get filed as "quoins", and are then never compared against anything. The
	# test was hiding its own failure. A piece is a piece.
	var pen := _worst_penetration(xf)
	print("  [1] interpenetrating pairs: %d (worst %.3f m)   %s"
			% [pen.pairs, pen.worst, "OK" if pen.pairs == 0 else "FAIL"])
	if pen.pairs > 0:
		print("      worst pair at y=%.2f / y=%.2f  (wall top is %.2f)"
				% [pen.at_a.y, pen.at_b.y, SIZE.y])

	# 2. NO OPEN NOTCH — every course of the wall must carry a corner stone.
	var courses := int(round(SIZE.y / a.course_height))
	var have := {}
	for t: Transform3D in quoin:
		have[int(floor(t.origin.y / a.course_height))] = true
	var missing: Array = []
	for ci in courses:
		if not have.has(ci):
			missing.append(ci)
	print("  [2] quoined courses %d/%d   missing %s   %s"
			% [have.size(), courses, missing, "OK" if missing.is_empty() else "FAIL"])

	# 3. BEDS MEET — the one the incompatible case is expected to fail.
	var beds_a := _beds(on_a)
	var beds_b := _beds(on_b)
	var unmatched := 0
	for y: float in beds_a:
		var best := 9.9
		for y2: float in beds_b:
			best = minf(best, absf(y - y2))
		if best > 0.01:
			unmatched += 1
	print("  [3] beds A %d  B %d   unmatched %d   %s"
			% [beds_a.size(), beds_b.size(), unmatched, "OK" if unmatched == 0 else "MISMATCH"])

	# 4. THE QUOIN ALTERNATES, which is what makes it read as toothed rather than as a pilaster.
	var dirs := {}
	for t: Transform3D in quoin:
		dirs[int(floor(t.origin.y / a.course_height))] = t.basis.x.normalized()
	var keys: Array = dirs.keys()
	keys.sort()
	var same := 0
	for i in range(1, keys.size()):
		if absf((dirs[keys[i]] as Vector3).dot(dirs[keys[i - 1]] as Vector3)) > 0.9:
			same += 1
	print("  [4] non-alternating quoin courses: %d of %d   %s"
			% [same, maxi(keys.size() - 1, 0), "OK" if same == 0 else "FAIL"])

	# 5. The two faces are actually distinguishable — otherwise the test proves nothing.
	print("  [5] mean colour  A %s   B %s" % [_mean(m, on_a), _mean(m, on_b)])
	m.queue_free()


## THE WHOLE CUBE: four dressed sides, alternating styles, so every face is inset at BOTH ends and
## all four arrises are quoined. The two-face case can pass while a face with two built neighbours
## quietly loses its far end, which is exactly the sort of thing that only shows up here.
func _all_four(a: GladeStyle, b: GladeStyle) -> void:
	print("\n=== ALL FOUR SIDES (alternating) ===")
	var m := GladeMass.new()
	m.size = SIZE
	m.style_left = a
	m.style_right = b
	m.style_front = b
	m.style_back = a
	root.add_child(m)
	m.rebuild()
	print("  stats: %s" % [m.stats])

	var h := SIZE * 0.5
	# Four corners, each the crossing of two centrelines.
	var corners := [Vector2(-h.x + a.depth * 0.5, -h.z + b.depth * 0.5),
			Vector2(-h.x + a.depth * 0.5, h.z - b.depth * 0.5),
			Vector2(h.x - a.depth * 0.5, -h.z + b.depth * 0.5),
			Vector2(h.x - a.depth * 0.5, h.z - b.depth * 0.5)]
	var per_corner := [0, 0, 0, 0]
	for t: Transform3D in m.snap_transforms:
		for ci in 4:
			var c: Vector2 = corners[ci]
			if absf(t.origin.x - c.x) < 0.06 and absf(t.origin.z - c.y) < 0.06:
				per_corner[ci] += 1
	var courses := int(round(SIZE.y / a.course_height))
	print("  quoins per corner: %s   (expect ~%d each)   %s"
			% [per_corner, courses,
					"OK" if per_corner.min() >= courses - 1 else "FAIL — a corner is bare"])
	print("  total pieces %d across %d faces" % [m.snap_transforms.size(), m.stats.get("faces", 0)])
	m.queue_free()


## Every pair of pieces, tested for real interpenetration.
##
## `TOLERANCE` forgives the jitter every masonry style has by design — `tilt_jitter`,
## `offset_jitter` and `depth_jitter` let neighbouring stones in one course kiss by a millimetre or
## two, and that is the look, not a defect. What it does NOT forgive is a stone standing a
## substantial fraction of its own thickness inside another, which is what an unmitred corner
## produces and what this exists to catch.
const TOLERANCE := 0.02


func _worst_penetration(all: Array[Transform3D]) -> Dictionary:
	var pairs := 0
	var worst := 0.0
	var at_a := Vector3.ZERO
	var at_b := Vector3.ZERO
	for i in all.size():
		var a := all[i]
		for j in range(i + 1, all.size()):
			var b := all[j]
			# cheap reject: nothing can overlap if the centres are further apart than the two
			# pieces' longest possible half-diagonals
			if a.origin.distance_squared_to(b.origin) > 1.5:
				continue
			var o := _overlap(a, b)
			if o > TOLERANCE:
				pairs += 1
				if o > worst:
					worst = o
					at_a = a.origin
					at_b = b.origin
	return {"pairs": pairs, "worst": worst, "at_a": at_a, "at_b": at_b}


## How far two oriented boxes penetrate, along the axis of least overlap. 0 when they are apart.
## Every GladeKit piece is a unit cube scaled by its transform, so the basis lengths ARE the extents.
func _overlap(a: Transform3D, b: Transform3D) -> float:
	var best := INF
	for t: Transform3D in [a, b]:
		for axis in 3:
			var n: Vector3 = t.basis[axis].normalized()
			var d := absf((b.origin - a.origin).dot(n))
			var gap := _extent(a, n) + _extent(b, n) - d
			if gap <= 0.0:
				return 0.0                     # a separating axis: they do not touch
			best = minf(best, gap)
	return best


func _extent(t: Transform3D, n: Vector3) -> float:
	return 0.5 * (absf(t.basis.x.dot(n)) + absf(t.basis.y.dot(n)) + absf(t.basis.z.dot(n)))


func _beds(list: Array[Transform3D]) -> Array:
	var out: Array = []
	for t: Transform3D in list:
		var y: float = snappedf(t.origin.y, 0.005)
		if not out.has(y):
			out.append(y)
	out.sort()
	return out


func _mean(m: GladeMass, list: Array[Transform3D]) -> String:
	if list.is_empty():
		return "-"
	var c := Color(0, 0, 0)
	for t: Transform3D in list:
		var i := m.snap_transforms.find(t)
		if i >= 0 and i < m.snap_colors.size():
			c += m.snap_colors[i]
	c /= float(list.size())
	return "(%.2f %.2f %.2f)" % [c.r, c.g, c.b]
