extends RefCounted
## CHAPTER 6 — A MASS IS A SOLID, AND ITS SURFACE IS WHERE THE STONE STOPS.
##
## The other chapters take a `GladeWall` apart. This one takes the other authoring primitive apart,
## and answers the four questions a `GladeMass` actually raises when you first meet one:
##
##   IS IT A MESH?  Yes, and step 3 shows both kinds at once. A mass is a plain `Node3D` that on
##                  every rebuild throws everything away and re-adopts `MeshInstance3D`s carrying real
##                  `ArrayMesh`es plus a `MultiMeshInstance3D` per brick variant, all with
##                  `INTERNAL_MODE_BACK` — which is why the scene tree looks empty and why the
##                  wireframe here walks `get_children(true)`.
##   ARE THEY POLYGONS?  The `wireframe` box draws the actual index buffers. Nothing in
##                  `atlas_wire.gd` knows what a wall is; if a triangle is on screen it is in a mesh.
##   WHERE DOES THE GEOMETRY COME FROM?  Steps 1-2. A volume, its faces, and one face turned into a
##                  fillable domain — after which every wall fill strategy works on it unchanged,
##                  because `GladeSurfacePlanar` and `GladeWallFrame` are the same interface.
##   HOW DO TWO MASSES BLEND?  Steps 6-7, and the answer is that they do not blend. There is no CSG
##                  in this addon. A merge is a per-piece PREDICATE plus a 1-D interval solved by
##                  bisection, and step 6 draws that interval.
##
## THIS CHAPTER PUTS REAL NODES IN THE TREE, like `chapter_junctions.gd` and unlike the rest. Merging
## is genuinely about the scene — masses find their siblings by walking up to a shared
## `GladeBuilding` — so driving it through `atlas_rig.gd` would fake the interesting half and prove
## nothing. `atlas_rig` is deliberately unused here.
##
## THE BADGE. Steps 1-5 rebuild the same intent twice and compare every placement: same intent, same
## building, or the seeded randomness has stopped being seeded. Steps 6-7 assert the stronger claim
## the doc rests on — a merge SUPPRESSES, it does not re-mesh — by building the host alone, recording
## its stones, then adding the sibling and checking that every stone standing OUTSIDE the sibling is
## still there and has not moved. If merging ever perturbs a stone it had no business touching, one
## box moving would ripple through the whole building and the badge goes red.
##
## Companion doc: `docs/gladekit-masses.md`.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Wire := preload("res://scripts/dev/atlas/atlas_wire.gd")

const STYLE_PANEL := "res://addons/gladekit/styles/panel_stone.tres"
const STYLE_STONE := "res://addons/gladekit/styles/alsace_stone.tres"
const STYLE_QUOIN := "res://addons/gladekit/styles/crypt_stone.tres"

## Each step sets the scene up its own way and points the reading pane at the class it is about.
const STEPS := [
	{"name": "the volume", "doc": "GladeVolume",
		"note": "No style at all, so nothing is filled and the node draws its BLOCKOUT. This is the whole of the intent: one convex solid, and the faces it hands out. Numbers are face indices — the order you will name them in."},
	{"name": "a face becomes a domain", "doc": "GladeSurfacePlanar",
		"note": "One face, turned into something a fill can be laid on. Yellow is the face plane; blue is where plumb() answers — HALF A DEPTH INWARD, so the outer face of every brick lands on the volume. That one offset is the entire difference from a wall, whose curve runs down the middle of its stones."},
	{"name": "the fill, and what a wall is made of", "doc": "GladeFillPanel",
		"note": "Cycle the fill and watch the COUNTS, not the picture. PANEL commits a couple of ArrayMesh triangles per face through SurfaceTool — the only thing here with UVs — and hands the whole look to a texture. MASONRY commits nothing of its own: one unit chamfered box, a few hundred instance transforms. MODULE is the same trick one order up, a handful of wall-sized panels, and an opening SWAPS one rather than cutting it. Three answers to what a wall is; the piece count is the argument."},
	{"name": "the arris", "doc": "GladeStageCorners",
		"note": "Two flat faces meet in a razor edge and no material fixes that. Quoins make the angle out of stone; bevel answers it with one quad. Turn the INSET off to see what the corner does without it — that overlap was measured at 0.220 m on a 0.46 m wall."},
	{"name": "hollow — a shell, not a block", "doc": "GladeMass",
		"note": "The inner skin, the top frame, the coping and the floor deck. A hollow mass has no lid: skinning the cap as well put a roof over the opening and the room vanished behind it."},
	{"name": "the hole", "doc": "GladeReveal",
		"note": "Drag it anywhere. The opening is subtracted from the face's OUTLINE at continuous coordinates — no grid, no snapping, no matching module — and the sides of the hole are four quads laid between the two faces it runs between. Set depth and it stops inside the block instead: a niche, with a back on it. Name a face and it cuts a floor."},
	{"name": "the merge — suppression, not union", "doc": "GladeClaimCut",
		"note": "Two masses under ONE GladeBuilding. Neither wins and nothing is re-meshed: each face declines to build the part of itself inside its sibling, and (A outside B) union (B outside A) IS the merged outline. The green bar is the interval GladeClaimCut solved by bisection; red is what it took. A partition is the same test with a minus sign — build ONLY where buried."},
	{"name": "rank — a contest, not a merge", "doc": "GladeClaim",
		"note": "The same two masses with NO shared GladeBuilding, so they are rivals rather than wings. A strictly higher rank wins. Equal ranks deliberately do nothing at all: a scene built before junctions existed stays byte-identical until somebody sets a number. Leave B at 0 and watch nothing happen."},
]

const HOLE_STEP := 5
## Which step puts the sibling under the SAME building. This one line is the whole difference between
## the last two steps, and it is the difference between merging and ranking: a merge is declared by a
## shared `GladeBuilding` ancestor and is never inferred from overlap.
const MERGE_STEP := 6
const RANK_STEP := 7

const FILLS := ["PANEL", "MASONRY", "MODULE"]
const STYLE_MODULE := "res://addons/gladekit/styles/module_block.tres"

const HOLE_FACES := ["front", "top", "left"]
const HOLE_SHAPES := ["RECT", "ARCHED", "ROUND"]

## Kept beside `FILLS` so the two lists cannot drift apart.
const FILLS_STYLE := [STYLE_PANEL, STYLE_STONE, STYLE_MODULE]

var atlas

var _step := 0
var _wireframe := false
## 0 PANEL, 1 MASONRY, 2 MODULE — the three answers to "what is a wall made of", and the counts line
## in the panel is the whole argument between them.
var _fill := 0
var _hollow := false
var _prism := false
var _quoins := true
var _inset := true
var _partition := false
var _sides := 8
var _size := Vector3(5.0, 4.0, 4.0)
var _bevel := 0.0
var _oversail := 0.0
var _offset := 2.6
var _rank_b := 0
var _hole_at := 0.0                            ## along the face, relative to its middle
var _hole_up := 1.0
var _hole_w := 1.1
var _hole_h := 1.5
var _hole_depth := 0.0                         ## 0 = all the way through, or as far as it can go
var _hole_shape := 0
var _hole_face := 0

var _holder: Node3D
var _overlay: Node3D
var _wire: Node3D
var _building: GladeBuilding
var _a: GladeMass
var _b: GladeMass
var _badge := {"ok": true, "text": ""}


func setup() -> void:
	_holder = Node3D.new()
	atlas.stage.add_child(_holder)
	_overlay = Node3D.new()
	atlas.stage.add_child(_overlay)
	_rebuild()


func teardown() -> void:
	_drop_wire()


func on_step(dir: int) -> void:
	_step = posmod(_step + dir, STEPS.size())
	# A STEP SETS ITS OWN SCENE UP. Arriving at the shell step with `hollow` off shows the previous
	# step again and reads as a broken button; the checkbox is still there to turn it back off.
	if _step == 4:
		_hollow = true
	_rebuild()
	atlas.refresh()


# ---------------------------------------------------------------- building --------------------


## THE WHOLE SCENE, EVERY TIME. A mass rebuild is already a full teardown — there is no incremental
## path in the node and there should not be — so a chapter that tried to mutate in place would be
## modelling something the addon does not do.
func _rebuild() -> void:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.free()
	_a = null
	_b = null

	_building = GladeBuilding.new()
	_building.name = "Building"
	_holder.add_child(_building)

	_a = _mass("A", Vector3.ZERO)
	_building.add_child(_a)

	# SOLO FIRST, and only when there will be a sibling. The merge invariant cannot be stated without
	# a picture of the host standing alone, and the only honest way to get one is to build it.
	var solo: Array[Transform3D] = []
	if _wants_sibling():
		_a.rebuild()
		solo = _a.snap_transforms.duplicate()
		_b = _mass("B", Vector3(_offset, 0.0, 1.4))
		_b.size = Vector3(3.0, 5.6, 3.0)
		if _step == MERGE_STEP:
			_b.partition = _partition
			_building.add_child(_b)          # a wing: same building, so they merge
		else:
			_b.junction_rank = _rank_b
			_holder.add_child(_b)            # a rival: no shared building, so rank decides

	# BOTH IN THE TREE BEFORE EITHER BUILDS, so each can see the other's claim. A mass publishes its
	# volume from intent alone, so this needs no ordering beyond "everybody is present".
	_a.rebuild()
	if _b != null:
		_b.rebuild()

	_check(solo)
	_draw()
	_refresh_wire()


func _mass(n: String, at: Vector3) -> GladeMass:
	var m := GladeMass.new()
	m.name = n
	m.position = at
	m.size = _size
	m.rng_seed = hash(n) % 97
	m.generate_collision = false                   # nothing here walks; a body is one more thing to free
	# STEP 1 LEAVES THE STYLE OFF ON PURPOSE. With no style nothing is filled and the node draws its
	# blockout, which is the only state in which the domain annotation is readable — the arrows are
	# inside the wall the moment there is one.
	if _step >= 2:
		m.style = load(FILLS_STYLE[_fill])
	if _step >= 3:
		m.arris_quoins = _quoins
		m.bevel = _bevel
		if _quoins:
			m.style_quoin = load(STYLE_QUOIN)
		# THE INSET, TURNED OFF. `_inset()` is private and rightly so, but the knob it reads is not:
		# a quoin style with `corner_mitre` off takes the same branch that returns 0, which is exactly
		# the corner this step exists to show you.
		if not _inset and m.style_quoin != null:
			var q: GladeStyle = (m.style_quoin as GladeStyle).duplicate()
			q.corner_mitre = false
			m.style_quoin = q
	if _step >= 4:
		m.hollow = _hollow
		m.coping_oversail = _oversail
		if _hollow:
			m.style_inside = load(STYLE_PANEL)
			m.style_floor = load(STYLE_PANEL)
	if _prism:
		m.shape = GladeMass.Shape.PRISM
		m.sides = _sides
	if _step == HOLE_STEP and n == "A":
		m.add_child(_opening())
	return m


## THE MARKER, WHICH IS THE WHOLE INTENT. Everything about the hole is on it — where, how big, what
## shape, how deep, and which face when the face cannot be worked out (see `GladeOpening.face`).
func _opening() -> GladeOpening:
	var o := GladeOpening.new()
	o.width = _hole_w
	o.height = _hole_h
	o.shape = _hole_shape as GladeOpening.Shape
	o.depth = _hole_depth
	o.sill_height = 0.0
	var key: String = HOLE_FACES[_hole_face]
	o.face = "" if key == "front" else key
	# The marker is placed IN THE MASS'S OWN SPACE against the face it belongs to, which is what a
	# person dragging one does. On a cap it says where; on a wall it says how far along and how high.
	match key:
		"top":
			o.position = Vector3(_hole_at, _size.y, _hole_up - 1.0)
		"left":
			o.position = Vector3(-_size.x * 0.5, _hole_up, _hole_at)
		_:
			o.position = Vector3(_hole_at, _hole_up, -_size.z * 0.5)
	return o


func _wants_sibling() -> bool:
	return _step >= MERGE_STEP


# ---------------------------------------------------------------- the badge -------------------


## Steps 1-5: the same intent twice gives the same building. Steps 6-7: the merge took nothing it
## should not have. See the class header for why these two and not something friendlier.
func _check(solo: Array[Transform3D]) -> void:
	if _b == null:
		var first := _a.snap_transforms.duplicate()
		_a.rebuild()
		var second := _a.snap_transforms
		if first.size() != second.size():
			_badge = {"ok": false,
				"text": "NOT DETERMINISTIC: %d pieces then %d" % [first.size(), second.size()]}
			return
		for i in first.size():
			if not first[i].is_equal_approx(second[i]):
				_badge = {"ok": false, "text": "NOT DETERMINISTIC: piece %d moved" % i}
				return
		_badge = {"ok": true, "text": "deterministic ✓ %d pieces, twice" % first.size()}
		return

	# THE SUPPRESSION INVARIANT. Every stone the host had while standing alone, whose origin is not
	# inside the sibling, must still be standing exactly where it was.
	var vol: GladeVolume = (_b.junction_volumes() as Array)[0]
	var now := {}
	for t: Transform3D in _a.snap_transforms:
		now[_key(t.origin)] = true
	var expected := 0
	var lost := 0
	# `snap_transforms` is in the MASS'S OWN SPACE — that is where every emitter works — and a claim
	# volume is in world space. One conversion, in the one direction, is the whole of it.
	for t: Transform3D in solo:
		if vol.contains_near(_a.global_transform * t.origin, 0.002):
			continue                               # standing in B: fair game
		expected += 1
		if not now.has(_key(t.origin)):
			lost += 1
	var removed := solo.size() - _a.snap_transforms.size()
	if lost > 0:
		_badge = {"ok": false,
			"text": "PERTURBED %d of %d pieces outside B" % [lost, expected]}
	else:
		_badge = {"ok": true, "text": "%d pieces outside B untouched ✓ · %d removed"
				% [expected, removed]}


## A placement's identity, to a tenth of a millimetre. Comparing `Transform3D`s directly would ask
## about the scale and basis too, and a stone that is present and unmoved is the whole claim.
static func _key(p: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [p.x, p.y, p.z]


# ---------------------------------------------------------------- the wireframe ---------------


func _drop_wire() -> void:
	if _wire != null and is_instance_valid(_wire):
		_wire.queue_free()
	_wire = null


func _refresh_wire() -> void:
	_drop_wire()
	if not _wireframe:
		return
	_wire = Wire.edges(_holder)
	atlas.stage.add_child(_wire)


# ---------------------------------------------------------------- the annotations -------------


func _draw() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	if _a == null:
		return
	var vols: Array = _a.junction_volumes()
	if vols.is_empty():
		return
	var vol: GladeVolume = vols[0]
	var faces: Array = vol.faces()

	match _step:
		0: _draw_faces(faces)
		1: _draw_domain(faces)
		MERGE_STEP, RANK_STEP: _draw_merge(faces)


## Face index and outward normal, straight off `GladeVolume.faces()`. These are the numbers the
## per-face style and material slots are keyed by, so they are worth being able to point at.
func _draw_faces(faces: Array) -> void:
	for i in faces.size():
		var poly: PackedVector3Array = faces[i].polygon
		if poly.size() < 3:
			continue
		var mid := _centre(poly)
		var n: Vector3 = faces[i].normal
		_arrow(mid, n, Color(0.45, 0.85, 1.0), 0.9)
		_label("%d  %s" % [i, _a.face_key(i)], mid + n * 1.05, Color(0.9, 0.95, 1.0))


## The domain of one upright face: its origin corner, its two axes, and the gap between the face
## plane and where the stone's centreline actually sits.
func _draw_domain(faces: Array) -> void:
	var i := _front_face(faces)
	if i < 0:
		return
	var st := _style_of(i)
	if st == null:
		return
	var s := GladeSurfacePlanar.from_face(faces[i], st.depth)
	if s.length <= 0.05:
		return

	# the face itself, in yellow: where the intent says the wall is
	var poly: PackedVector3Array = faces[i].polygon
	var ring := poly.duplicate()
	ring.append(poly[0])
	_line(ring, Color(1.0, 0.85, 0.35))

	# u = 0 and u = length are the face's own EDGES, not a centreline's ends — the reason a mass
	# needed its own inset arithmetic at a corner.
	var a := s.plumb(0.0)
	var b := s.plumb(s.length)
	_line(PackedVector3Array([a, b]), Color(0.45, 0.9, 1.0))
	_line(PackedVector3Array([a, a + Vector3.UP * s.height]), Color(0.45, 0.9, 1.0))

	_arrow(s.origin, (b - a).normalized(), Color(1.0, 0.35, 0.35), 1.1)   # X — along the face
	_arrow(s.origin, s.rise(), Color(0.4, 1.0, 0.45), 1.1)                # Y — up the face
	_arrow(s.origin, s.normal, Color(0.4, 0.6, 1.0), 1.1)                 # Z — out of the solid
	_label("origin", s.origin, Color(1.0, 0.9, 0.5))
	_label("plumb() — %.3f m in" % (s.depth * 0.5), a, Color(0.5, 0.9, 1.0))


## THE CUT, AS THE ONE-DIMENSIONAL PROBLEM IT ACTUALLY IS.
##
## `GladeClaimCut` is handed a span and a mapping from a coordinate on it to a world point, and hands
## back the intervals left standing. Nothing about it is aware of triangles. Drawing the answer as a
## bar along the face is the most literal possible picture of what "the merge" means.
func _draw_merge(faces: Array) -> void:
	if _b == null:
		return
	for v: GladeVolume in (_b.junction_volumes() as Array):
		_draw_volume(v, Color(1.0, 0.45, 0.35))
	for v: GladeVolume in (_a.junction_volumes() as Array):
		_draw_volume(v, Color(0.35, 0.85, 1.0))

	var i := _front_face(faces)
	if i < 0:
		return
	var st := _style_of(i)
	if st == null:
		return
	var s := GladeSurfacePlanar.from_face(faces[i], st.depth)
	if s.length <= 0.05:
		return
	var claim := GladeClaim.new([], _a.junction_rank, 0, func(p: Vector3) -> Vector3: return p)
	if _step == MERGE_STEP:
		claim.merged = _b.junction_volumes()
		claim.partition = _partition
	else:
		claim.volumes = _b.junction_volumes()
	var y := Vector3.UP * (s.height * 0.5)
	var at := func(u: float) -> Vector3: return s.plumb(u) + y
	var kept: Array = GladeClaimCut.intervals(claim, at, 0.0, s.length)

	# red first, the whole span, then green over whatever survived: the difference IS the bite.
	# Stood well off the face: `no_depth_test` puts the bar in front of the stone either way, but a
	# line lying ON the wall reads as part of it, and this is a statement ABOUT the wall.
	var lift := s.normal * 0.5
	_line(PackedVector3Array([at.call(0.0) + lift, at.call(s.length) + lift]),
			Color(1.0, 0.35, 0.3))
	for span: Array in kept:
		_line(PackedVector3Array([at.call(span[0]) + lift, at.call(span[1]) + lift]),
				Color(0.35, 1.0, 0.45))
		_label("%.2f" % span[0], at.call(span[0]) + lift, Color(0.6, 1.0, 0.7))
		_label("%.2f" % span[1], at.call(span[1]) + lift, Color(0.6, 1.0, 0.7))


func _draw_volume(v: GladeVolume, col: Color) -> void:
	for f in v.faces():
		var poly: PackedVector3Array = f.polygon
		if poly.size() < 3:
			continue
		var ring := poly.duplicate()
		ring.append(poly[0])
		_line(ring, col)


## The style face `i` carries, falling back to the one it WOULD carry — step 1 deliberately leaves
## the mass unstyled, and the domain it draws still has a thickness because a domain's depth is a
## property of the face's style rather than of the solid.
func _style_of(i: int) -> GladeStyle:
	var sty: GladeStyle = _a.face_style(i)
	if sty == null:
		sty = load(FILLS_STYLE[_fill])
	return GladeUtil.current_style(sty)


## The face pointing at the camera's usual side (-Z), or the first upright one there is.
func _front_face(faces: Array) -> int:
	var best := -1
	var best_dot := -INF
	for i in faces.size():
		var n: Vector3 = faces[i].normal
		if absf(n.y) > 0.2:
			continue
		if n.z < best_dot:
			continue
		best_dot = n.z
		best = i
	return best


# ---------------------------------------------------------------- overlay primitives ----------


func _line(pts: PackedVector3Array, col: Color) -> void:
	if pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in pts.size() - 1:
		im.surface_add_vertex(pts[i])
		im.surface_add_vertex(pts[i + 1])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = GladeDebug.overlay_material(col)
	_overlay.add_child(mi)


func _arrow(at: Vector3, dir: Vector3, col: Color, len_: float) -> void:
	var tip := at + dir * len_
	var side := dir.cross(Vector3.UP).normalized() * 0.1
	if side.length() < 0.01:
		side = Vector3.RIGHT * 0.1
	_line(PackedVector3Array([at, tip, tip, tip - dir * 0.22 + side,
			tip, tip - dir * 0.22 - side]), col)


func _label(text: String, at: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = col
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.outline_size = 6
	_overlay.add_child(l)


static func _centre(poly: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


# ---------------------------------------------------------------- the panel -------------------


func build_rows(box: VBoxContainer) -> void:
	var spec: Dictionary = STEPS[_step]
	atlas.set_badge(_badge.text, _badge.ok)

	var head := Label.new()
	head.text = "%d/%d  %s" % [_step + 1, STEPS.size(), spec.name]
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	var note := Label.new()
	note.text = spec.note
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(290, 0)
	note.add_theme_font_size_override("font_size", 11)
	box.add_child(note)

	Tuning.button(box, "◀  previous", func() -> void: on_step(-1))
	Tuning.button(box, "next  ▶", func() -> void: on_step(1))

	# --- what is actually on screen, in triangles -------------------------------------------
	Tuning.header(box, "the geometry")
	var counts := Label.new()
	counts.add_theme_font_size_override("font_size", 11)
	counts.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75))
	counts.text = Wire.summary(_holder)
	if _wire != null and bool(_wire.get_meta("truncated", false)):
		counts.text += "\n(wireframe truncated at %d lines)" % Wire.MAX_LINES
	box.add_child(counts)
	Tuning.check(box, "wireframe", _wireframe,
			func(on: bool) -> void: _wireframe = on; _refresh_wire(); atlas.refresh())

	if not _a.stats.is_empty():
		var st := Label.new()
		st.add_theme_font_size_override("font_size", 11)
		st.text = "stats  %s" % _fmt(_a.stats)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(290, 0)
		box.add_child(st)

	# --- the knobs this step is about, and only those ---------------------------------------
	Tuning.header(box, "intent")
	Tuning.slider(box, "size.x", 2.0, 10.0, 0.2, _size.x,
			func(v: float) -> void: _size.x = v; _rebuild(); atlas.refresh())
	Tuning.slider(box, "size.y", 2.0, 10.0, 0.2, _size.y,
			func(v: float) -> void: _size.y = v; _rebuild(); atlas.refresh())
	Tuning.slider(box, "size.z", 2.0, 10.0, 0.2, _size.z,
			func(v: float) -> void: _size.z = v; _rebuild(); atlas.refresh())
	Tuning.check(box, "PRISM instead of BOX", _prism,
			func(on: bool) -> void: _prism = on; _rebuild(); atlas.refresh())
	if _prism:
		Tuning.slider(box, "sides", 3.0, 20.0, 1.0, float(_sides),
				func(v: float) -> void: _sides = int(v); _rebuild(); atlas.refresh())

	if _step >= 2:
		Tuning.header(box, "fill")
		Tuning.button(box, "fill:  %s" % FILLS[_fill], func() -> void:
			_fill = (_fill + 1) % FILLS.size(); _rebuild(); atlas.refresh())
	if _step >= 3:
		Tuning.header(box, "the arris")
		Tuning.check(box, "arris_quoins", _quoins,
				func(on: bool) -> void: _quoins = on; _rebuild(); atlas.refresh())
		Tuning.check(box, "inset the faces (corner_mitre)", _inset,
				func(on: bool) -> void: _inset = on; _rebuild(); atlas.refresh())
		Tuning.slider(box, "bevel", 0.0, 0.3, 0.01, _bevel,
				func(v: float) -> void: _bevel = v; _rebuild(); atlas.refresh())
	if _step >= 4:
		Tuning.header(box, "the shell")
		Tuning.check(box, "hollow", _hollow,
				func(on: bool) -> void: _hollow = on; _rebuild(); atlas.refresh())
		Tuning.slider(box, "coping_oversail", 0.0, 0.4, 0.01, _oversail,
				func(v: float) -> void: _oversail = v; _rebuild(); atlas.refresh())
	if _step == HOLE_STEP:
		Tuning.header(box, "the opening")
		Tuning.button(box, "face:  %s" % HOLE_FACES[_hole_face], func() -> void:
			_hole_face = (_hole_face + 1) % HOLE_FACES.size(); _rebuild(); atlas.refresh())
		Tuning.button(box, "shape:  %s" % HOLE_SHAPES[_hole_shape], func() -> void:
			_hole_shape = (_hole_shape + 1) % HOLE_SHAPES.size(); _rebuild(); atlas.refresh())
		Tuning.slider(box, "along the face", -_size.x * 0.5, _size.x * 0.5, 0.05, _hole_at,
				func(v: float) -> void: _hole_at = v; _rebuild(); atlas.refresh())
		Tuning.slider(box, "up the face", 0.0, 3.0, 0.05, _hole_up,
				func(v: float) -> void: _hole_up = v; _rebuild(); atlas.refresh())
		Tuning.slider(box, "width", 0.4, 3.0, 0.05, _hole_w,
				func(v: float) -> void: _hole_w = v; _rebuild(); atlas.refresh())
		Tuning.slider(box, "height", 0.4, 3.0, 0.05, _hole_h,
				func(v: float) -> void: _hole_h = v; _rebuild(); atlas.refresh())
		Tuning.slider(box, "depth (0 = through)", 0.0, 1.5, 0.05, _hole_depth,
				func(v: float) -> void: _hole_depth = v; _rebuild(); atlas.refresh())
	if _step >= MERGE_STEP:
		Tuning.header(box, "the sibling")
		Tuning.slider(box, "B offset x", 0.0, 6.0, 0.1, _offset,
				func(v: float) -> void: _offset = v; _rebuild(); atlas.refresh())
	if _step == MERGE_STEP:
		Tuning.check(box, "B is a partition", _partition,
				func(on: bool) -> void: _partition = on; _rebuild(); atlas.refresh())
	if _step == RANK_STEP:
		Tuning.slider(box, "B junction_rank (A is 0)", 0.0, 8.0, 1.0, float(_rank_b),
				func(v: float) -> void: _rank_b = int(v); _rebuild(); atlas.refresh())

	# THE READING PANE FOLLOWS THE TOGGLE on the fill step, because the whole step is the contrast:
	# leaving `GladeFillPanel` on screen next to a wall built of instanced stone is the panel telling
	# a small lie, and a panel that can be wrong is worse than none.
	var doc: String = spec.doc
	if _step == 2:
		doc = ["GladeFillPanel", "GladeFillMasonry", "GladeFillModule"][_fill]
	atlas.show_class(doc)


static func _fmt(d: Dictionary) -> String:
	var out := PackedStringArray()
	for k: Variant in d:
		out.append("%s %s" % [k, d[k]])
	return " · ".join(out)
