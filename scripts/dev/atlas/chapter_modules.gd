extends RefCounted
## CHAPTER 2 — THE MODULE MAP, derived from the source rather than drawn by hand.
##
## Boxes are classes, grouped into columns by package, in dependency order:
##
##     data  ──▶  core  ──▶  generate  ──▶  nodes  ──▶  editor
##
## Every arrow is scanned out of the addon's own files by `atlas_graph.gd`. A diagram maintained by
## hand is wrong by the second refactor; this one follows the code. Click a box to read its header.
##
## RED ARROWS POINT THE WRONG WAY down that ordering. There are three, and they are real: the
## opening and prop stages ask `is GladeOpening` to tell an author-placed hole from a path crossing,
## and the tee stage asks a neighbouring `GladeWall` for its style. Marker classes are pure intent
## with almost no logic, so the coupling is thin — but it IS coupling, and a map that hid it would
## be a worse map.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Graph := preload("res://scripts/dev/atlas/atlas_graph.gd")
const GraphView := preload("res://scripts/dev/atlas/atlas_graph_view.gd")

var atlas

var _layer: CanvasLayer
var _view: Control
var _g := {}
var _selected := ""


func setup() -> void:
	_g = Graph.build()
	_layer = CanvasLayer.new()
	_layer.layer = 30
	atlas.stage.add_child(_layer)
	_view = Control.new()
	_view.set_script(GraphView)
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.graph = _g
	_view.on_pick = func(cls: String) -> void:
		_selected = cls
		_view.selected = cls
		_view.queue_redraw()
		atlas.refresh()
	_layer.add_child(_view)
	_selected = "GladeWallContext"
	_view.selected = _selected


func teardown() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()


func on_step(dir: int) -> void:
	# step through the classes of the selected package, so the keyboard can tour the map too
	var names: Array = []
	for l in Graph.LAYERS:
		names.append_array(_g.by_layer[l])
	if names.is_empty():
		return
	var i := names.find(_selected)
	_selected = names[posmod(i + dir, names.size())]
	_view.selected = _selected
	_view.queue_redraw()
	atlas.refresh()


func build_rows(box: VBoxContainer) -> void:
	var back: Array = Graph.back_edges(_g)
	var head := Label.new()
	head.text = "%d classes · %d edges" % [_g.classes.size(), _g.edges.size()]
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	var arrow := Label.new()
	arrow.add_theme_font_size_override("font_size", 11)
	arrow.text = "data ▸ core ▸ generate ▸ nodes ▸ editor\nthe arrow points one way"
	box.add_child(arrow)

	var b := Label.new()
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(296, 0)
	b.add_theme_font_size_override("font_size", 11)
	if back.is_empty():
		b.text = "no back-edges"
		b.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	else:
		var lines := PackedStringArray(["%d back-edges (real, see header):" % back.size()])
		for e: Array in back:
			lines.append("  %s → %s" % [e[0].replace("Glade", ""), e[1].replace("Glade", "")])
		b.text = "\n".join(lines)
		b.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	box.add_child(b)

	if _selected != "":
		Tuning.header(box, _selected)
		var n: Dictionary = Graph.neighbours_of(_g, _selected)
		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(296, 0)
		info.add_theme_font_size_override("font_size", 11)
		info.text = "package: %s · %d lines\n\nuses (%d):\n  %s\n\nused by (%d):\n  %s" % [
				_g.classes[_selected].layer, _g.classes[_selected].lines,
				(n.uses as Array).size(),
				", ".join(_short(n.uses)) if not (n.uses as Array).is_empty() else "—",
				(n.used_by as Array).size(),
				", ".join(_short(n.used_by)) if not (n.used_by as Array).is_empty() else "—"]
		box.add_child(info)
		atlas.show_class(_selected)

	Tuning.header(box, "jump")
	for l: String in Graph.LAYERS:
		var arr: Array = _g.by_layer.get(l, [])
		if arr.is_empty():
			continue
		var lb := Tuning.button(box, "%s (%d)" % [l, arr.size()], func(): _pick_first(l))
		lb.add_theme_font_size_override("font_size", 11)


func _pick_first(layer: String) -> void:
	var arr: Array = _g.by_layer.get(layer, [])
	if arr.is_empty():
		return
	_selected = arr[0]
	_view.selected = _selected
	_view.queue_redraw()
	atlas.refresh()


static func _short(names: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in names:
		out.append(n.replace("Glade", ""))
	return out
