extends Control
## THE MODULE MAP, drawn. A column per package in dependency order, a box per class, an arrow per
## edge, and everything touching the selected box lit up so one class's neighbourhood is legible in
## a graph of a hundred and forty edges.
##
## Layout is deliberately dumb — columns and rows, no force-directed anything. The interesting
## property is WHICH WAY THE ARROWS POINT, and a tidy left-to-right grid shows that at a glance
## where a spring layout would hide it in a hairball.

const Graph := preload("res://scripts/dev/atlas/atlas_graph.gd")

const GAP_Y := 3.0
const ROW_H := 17.0
const INSET_L := 356.0                         # clear of the controls panel
const INSET_R := 424.0                         # ...and the reading panel
const TOP := 40.0

const COL_BG := Color(0.13, 0.14, 0.17, 0.92)
const COL_EDGE := Color(0.42, 0.46, 0.54, 0.30)
const COL_HOT := Color(0.45, 0.85, 1.0, 0.95)
const COL_BACK := Color(1.0, 0.42, 0.32, 0.85)
const COL_SEL := Color(1.0, 0.82, 0.35)

var graph := {}
var selected := ""
var on_pick: Callable

var _rects := {}                               ## class -> Rect2, rebuilt on layout


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (e as InputEventMouseButton).position
		for cls: String in _rects:
			if (_rects[cls] as Rect2).has_point(p):
				if on_pick.is_valid():
					on_pick.call(cls)
				accept_event()
				return


func _draw() -> void:
	if graph.is_empty():
		return
	_layout()
	var font := ThemeDB.fallback_font
	var back := {}
	for e: Array in Graph.back_edges(graph):
		back["%s>%s" % [e[0], e[1]]] = true

	# edges first, so boxes sit on top of them
	for e: Array in graph.edges:
		if not _rects.has(e[0]) or not _rects.has(e[1]):
			continue
		var is_back: bool = back.has("%s>%s" % [e[0], e[1]])
		var touches: bool = selected != "" and (e[0] == selected or e[1] == selected)
		if selected != "" and not touches and not is_back:
			continue                           # a selection mutes everything unrelated
		var a: Rect2 = _rects[e[0]]
		var b: Rect2 = _rects[e[1]]
		var from := Vector2(a.position.x + a.size.x, a.get_center().y)
		var to := Vector2(b.position.x, b.get_center().y)
		if b.position.x < a.position.x:        # pointing left: leave from the left edge
			from = Vector2(a.position.x, a.get_center().y)
			to = Vector2(b.position.x + b.size.x, b.get_center().y)
		var col := COL_BACK if is_back else (COL_HOT if touches else COL_EDGE)
		draw_line(from, to, col, 2.0 if (touches or is_back) else 1.0, true)
		_arrow_head(to, (to - from).normalized(), col)

	# then the boxes
	for cls: String in _rects:
		var r: Rect2 = _rects[cls]
		var sel := cls == selected
		draw_rect(r, COL_BG, true)
		draw_rect(r, COL_SEL if sel else COL_EDGE, false, 2.0 if sel else 1.0)
		draw_string(font, r.position + Vector2(6, 12), cls.replace("Glade", ""),
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, 11,
				COL_SEL if sel else Color(0.86, 0.88, 0.92))

	# column headings, positioned from the boxes so they cannot drift out of step with them
	for l: String in Graph.LAYERS:
		var arr: Array = graph.by_layer.get(l, [])
		if arr.is_empty() or not _rects.has(arr[0]):
			continue
		var r: Rect2 = _rects[arr[0]]
		draw_string(font, Vector2(r.position.x, TOP - 10), "%s/" % l,
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 13, Color(0.55, 0.75, 1.0))


## Columns sized to whatever the two panels leave, so the map fits any window rather than running
## underneath the reading pane at one particular resolution.
func _layout() -> void:
	_rects.clear()
	var used: Array = []
	for l: String in Graph.LAYERS:
		if not (graph.by_layer.get(l, []) as Array).is_empty():
			used.append(l)
	if used.is_empty():
		return
	var avail: float = maxf(size.x - INSET_L - INSET_R, 320.0)
	var col_w: float = avail / used.size()
	var box := Vector2(maxf(col_w - 16.0, 60.0), ROW_H)
	var x := INSET_L
	for l: String in used:
		var y := TOP
		for cls: String in graph.by_layer[l]:
			_rects[cls] = Rect2(Vector2(x, y), box)
			y += ROW_H + GAP_Y
		x += col_w


func _arrow_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	if dir.length() < 0.01:
		return
	var n := dir.orthogonal() * 3.5
	draw_line(tip, tip - dir * 7.0 + n, col, 1.5, true)
	draw_line(tip, tip - dir * 7.0 - n, col, 1.5, true)
