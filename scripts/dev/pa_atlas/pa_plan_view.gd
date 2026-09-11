extends Control
## THE PLAN VIEW — the tree drawn top-down, metres to pixels, AS IT WAS AFTER A STEP.
##
## Every cell, seed, gate, fixture and wall carries the step of the operator that made it (the
## generator's trace), so drawing "the plan at step S" is a filter, never a rebuild: what came
## after S is not drawn, what came exactly at S is warmed in the accent colour, what came before
## is at rest. The focus cell (the chapter's) is bright, its descendants with it, its ancestors a
## ghost outline, everything else faint — the layout lab's plan with the atlas's dimming.
##
## Click a cell to drill into it; wheel zooms at the cursor; drag pans; F refits.

var atlas                                      ## the PaAtlas root, injected
var k := 4.0                                   ## pixels per metre
var off := Vector2.ZERO                        ## pixel offset of the plan origin

const BG := Color(0.11, 0.11, 0.13)
const GRID := Color(0.17, 0.17, 0.2)
const INK := Color(0.9, 0.9, 0.92)
const DIM := Color(0.55, 0.56, 0.6)
const WARN := Color(1.0, 0.55, 0.4)
const ACCENT := Color(1.0, 0.72, 0.25)
const WALL := Color(0.08, 0.08, 0.1)
const LEVEL_COL := [Color(0.2, 0.22, 0.27), Color(0.33, 0.42, 0.56), Color(0.62, 0.48, 0.3),
		Color(0.7, 0.57, 0.4), Color(0.38, 0.6, 0.48), Color(0.64, 0.72, 0.62)]
const CORRIDOR_COL := Color(0.4, 0.4, 0.42)

var _font: Font = ThemeDB.fallback_font
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_moved := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


# ---------------------------------------------------------------- the transform ------------


func fit(box: Rect2, plot: Rect2) -> void:
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	k = minf(plot.size.x / box.size.x, plot.size.y / box.size.y) * 0.88
	off = plot.get_center() - box.get_center() * k
	queue_redraw()


func to_px(p: Vector2) -> Vector2:
	return off + p * k


func to_m(px: Vector2) -> Vector2:
	return (px - off) / k


# ---------------------------------------------------------------- input --------------------


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			off = mb.position - (mb.position - off) * f
			k *= f
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag = true
				_drag_from = mb.position
				_drag_moved = false
			else:
				if _drag and not _drag_moved and mb.button_index == MOUSE_BUTTON_LEFT and atlas != null:
					atlas.pick_at(to_m(mb.position))
				_drag = false
			accept_event()
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		if (mm.position - _drag_from).length() > 4.0:
			_drag_moved = true
		if _drag_moved:
			off += mm.relative
			queue_redraw()
		accept_event()


# ---------------------------------------------------------------- the draw -----------------


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if atlas == null or atlas.rig.tree == null:
		return
	var s: int = atlas.step_global()
	var focus: RefCounted = atlas.focus()
	var floor: int = atlas.floor_shown()
	_draw_grid()
	var tree: RefCounted = atlas.rig.tree
	# pass 1: fills, parents first so children overdraw
	for c: RefCounted in tree.walk():
		_fill_cell(c, s, focus, floor)
	# pass 2: the lines and marks
	for c: RefCounted in tree.walk():
		_detail_cell(c, s, focus, floor)
	# the focus on top, and the player for scale
	if focus != null and visible_at(focus, s, floor):
		_outline(atlas.rig.polygon_at(focus, s), ACCENT, 2.5, 1.0)
		if not (focus.entrances as PackedVector2Array).is_empty():
			_figure(focus.entrances[0])
	_hud()


## The visible predicate: born by step S, on the floor shown (the root is floor 0 and always in).
func visible_at(cell: RefCounted, s: int, floor: int) -> bool:
	if atlas.rig.birth(cell) > s:
		return false
	return int(cell.floor) == floor or cell.parent == null


## 0 the focus, 1 a descendant, 2 an ancestor, 3 anything else.
func _rel(cell: RefCounted, focus: RefCounted) -> int:
	if focus == null:
		return 1
	if cell == focus:
		return 0
	var c: RefCounted = cell.parent
	while c != null:
		if c == focus:
			return 1
		c = c.parent
	c = focus.parent
	while c != null:
		if c == cell:
			return 2
		c = c.parent
	return 3


func _alpha(rel: int) -> float:
	match rel:
		0, 1: return 1.0
		2: return 0.28
		_: return 0.4


func _fill_cell(c: RefCounted, s: int, focus: RefCounted, floor: int) -> void:
	if not visible_at(c, s, floor):
		return
	var rel := _rel(c, focus)
	var a := _alpha(rel)
	var level: int = atlas.rig.level_of(c)
	var col: Color = CORRIDOR_COL if String(c.role) == "corridor" else LEVEL_COL[clampi(level, 0, 5)]
	if not bool(c.floored):
		col = col.lightened(0.25)
	var poly: PackedVector2Array = atlas.rig.polygon_at(c, s)
	if poly.size() < 3:
		return
	var px := PackedVector2Array()
	for p in poly:
		px.append(to_px(p))
	if rel != 2:
		draw_colored_polygon(px, Color(col, a))
	# holes, as background
	var hole_steps: PackedInt32Array = c.params.get("step_holes", PackedInt32Array())
	for hi in (c.holes as Array).size():
		if hi < hole_steps.size() and hole_steps[hi] > s:
			continue
		var hp := PackedVector2Array()
		for p in c.holes[hi]:
			hp.append(to_px(p))
		if hp.size() >= 3:
			draw_colored_polygon(hp, Color(BG, a))
	var warm: bool = atlas.rig.birth(c) == s
	var w := 2.0 if level == 2 or warm else 1.0
	var oc := ACCENT if warm else (INK if rel <= 1 else DIM)
	_outline(poly, oc, w, a if not warm else 1.0, not bool(c.floored))


func _detail_cell(c: RefCounted, s: int, focus: RefCounted, floor: int) -> void:
	if not visible_at(c, s, floor):
		return
	var rel := _rel(c, focus)
	var a := _alpha(rel)
	if rel == 2:
		a = 0.5
	# adjacency: the partition's edges, as walls or as dotted separations
	var wall_px := maxf(1.5, (float(c.wall_m) if float(c.wall_m) > 0.0 else 0.5) * k)
	var boundary: String = atlas.rig.boundary_at(c, s)
	for e: Dictionary in c.adjacency:
		var st := int(e.get("step", -1))
		if st > s:
			continue
		var col := ACCENT if st == s else Color(WALL, a)
		if boundary == "wall":
			draw_line(to_px(e.p), to_px(e.q), col, wall_px)
		else:
			draw_dashed_line(to_px(e.p), to_px(e.q), Color(col, a * 0.8), 1.0, 6.0)
	# own walls (a radial's rings)
	for w: Dictionary in c.walls:
		var st := int(w.get("step", -1))
		if st > s:
			continue
		var pts: PackedVector2Array = w.points
		var col := ACCENT if st == s else Color(WALL, a)
		for i in pts.size() - 1:
			draw_line(to_px(pts[i]), to_px(pts[i + 1]), col, maxf(1.5, 0.5 * k))
		if bool(w.get("closed", false)) and pts.size() > 2:
			draw_line(to_px(pts[pts.size() - 1]), to_px(pts[0]), col, maxf(1.5, 0.5 * k))
	# reserved and open: dashed
	for name in ["reserved", "open"]:
		var steps: PackedInt32Array = c.params.get("step_" + name, PackedInt32Array())
		var arr: Array = c.get(name)
		for i in arr.size():
			if i < steps.size() and steps[i] > s:
				continue
			var poly: PackedVector2Array = arr[i]
			var col := Color(0.6, 0.8, 1.0, a) if name == "open" else Color(1.0, 0.6, 0.6, a)
			for j in poly.size():
				draw_dashed_line(to_px(poly[j]), to_px(poly[(j + 1) % poly.size()]), col, 1.0, 5.0)
	# stairs
	for st: Dictionary in c.stairs:
		if int(st.get("step", -1)) > s:
			continue
		var p0: Vector2 = st.position
		var d := Vector2.from_angle(float(st.rotation))
		var n := Vector2(-d.y, d.x) * float(st.width) * 0.5
		var l: float = float(st.get("length", 3.0))
		var quad := PackedVector2Array([to_px(p0 - n), to_px(p0 + d * l - n), to_px(p0 + d * l + n), to_px(p0 + n)])
		draw_colored_polygon(quad, Color(0.85, 0.85, 0.6, a * 0.8))
		var steps_n := int(l / 0.28)
		for i in steps_n:
			var t := float(i) / float(steps_n)
			draw_line(to_px(p0 + d * l * t - n), to_px(p0 + d * l * t + n), Color(WALL, a * 0.5), 1.0)
	# gates: discs of their width
	for g: Dictionary in c.gates:
		var st := int(g.get("step", -1))
		if st > s:
			continue
		var r := maxf(3.0, float(g.width) * 0.5 * k)
		draw_circle(to_px(g.point), r, ACCENT if st == s else Color(0.95, 0.65, 0.3, a))
	# seeds, with the role's initial
	var ss := int(c.params.get("step_seeds", -1))
	if ss >= 0 and ss <= s:
		var seeds: PackedVector2Array = c.seeds
		var roles: PackedStringArray = c.seed_roles
		for i in seeds.size():
			var p := to_px(seeds[i])
			draw_circle(p, 4.0, ACCENT if ss == s else Color(1.0, 1.0, 0.8, a))
			if i < roles.size() and roles[i] != "" and k > 1.5:
				draw_string(_font, p + Vector2(6, 4), roles[i].substr(0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, a))
	# fixtures: rotated rects with the key's initial
	for f: Dictionary in c.fixtures:
		var st := int(f.get("step", -1))
		if st > s:
			continue
		var sz: Vector2 = f.size_m
		var d := Vector2.from_angle(float(f.rotation))
		var n := Vector2(-d.y, d.x)
		var p: Vector2 = f.position
		var hx := d * sz.x * 0.5
		var hy := n * sz.y * 0.5
		var quad := PackedVector2Array([to_px(p - hx - hy), to_px(p + hx - hy), to_px(p + hx + hy), to_px(p - hx + hy)])
		draw_colored_polygon(quad, ACCENT if st == s else Color(0.75, 0.6, 0.9, a * 0.9))
		if k > 6.0:
			draw_string(_font, to_px(p) + Vector2(-3, 4), String(f.key).substr(0, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(BG, a))
	# entrances: triangles on the border
	var es: PackedInt32Array = c.params.get("step_entrances", PackedInt32Array())
	var ents: PackedVector2Array = c.entrances
	for i in ents.size():
		if i < es.size() and es[i] > s:
			continue
		var p := to_px(ents[i])
		var r := 5.0 if c.parent != null else 8.0
		var col := Color(0.5, 1.0, 0.6, a)
		if i < es.size() and es[i] == s:
			col = ACCENT
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r), p + Vector2(-r, r)]), col)
	# the token, when there is room for it
	if k * sqrt(c.area()) > 26.0 and c.parent != null and rel <= 1:
		var ctr := to_px(c.centroid())
		draw_string(_font, ctr + Vector2(-8, 4), String(c.token), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, a))


func _outline(poly: PackedVector2Array, col: Color, w: float, a: float, dashed := false) -> void:
	if poly.size() < 2:
		return
	var c := Color(col, a)
	for i in poly.size():
		var p := to_px(poly[i])
		var q := to_px(poly[(i + 1) % poly.size()])
		if dashed:
			draw_dashed_line(p, q, c, w, 5.0)
		else:
			draw_line(p, q, c, w)


## A 1.8 m player at the entrance, for scale: the disc a body takes from above and its height
## as a bar.
func _figure(at: Vector2) -> void:
	var p := to_px(at)
	draw_circle(p, maxf(2.0, 0.25 * k), Color(1.0, 0.95, 0.5))
	draw_line(p + Vector2(0, 8), p + Vector2(1.8 * k, 8), Color(1.0, 0.95, 0.5), 2.0)
	if k > 2.0:
		draw_string(_font, p + Vector2(0, 22), "1.8 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.95, 0.5))


func _draw_grid() -> void:
	var step := 10.0 * k
	if step < 12.0:
		return
	var x := fmod(off.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
		x += step
	var y := fmod(off.y, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
		y += step


func _hud() -> void:
	var lines: PackedStringArray = atlas.hud_lines()
	var plot: Rect2 = atlas.plot_rect()
	var y := plot.position.y + 16.0
	for i in lines.size():
		var col := INK if i == 0 else (WARN if lines[i].begins_with("!") else DIM)
		draw_string(_font, Vector2(plot.position.x + 8.0, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if i == 0 else 12, col)
		y += 17.0


## What is visible at a step: the atlas's self-test proves the counts only grow.
func count_visible(s: int, floor: int) -> Dictionary:
	var n := {"cells": 0, "gates": 0, "fixtures": 0, "adjacency": 0, "seeds": 0}
	for c: RefCounted in atlas.rig.tree.walk():
		if not visible_at(c, s, floor):
			continue
		n.cells += 1
		for g: Dictionary in c.gates:
			if int(g.get("step", -1)) <= s:
				n.gates += 1
		for f: Dictionary in c.fixtures:
			if int(f.get("step", -1)) <= s:
				n.fixtures += 1
		for e: Dictionary in c.adjacency:
			if int(e.get("step", -1)) <= s:
				n.adjacency += 1
		var ss := int(c.params.get("step_seeds", -1))
		if ss >= 0 and ss <= s:
			n.seeds += (c.seeds as PackedVector2Array).size()
	return n
