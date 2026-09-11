extends RefCounted
## CHAPTER 1 — THE PIPELINE, one stage at a time.
##
## The wall is built to step N and drawn with the current stage's pieces at full colour and
## everything before it desaturated, so the thing you are reading about is the thing you can see.
## Step 0 shows only the INTENT — the curve and the markers — because that really is all the .tscn
## stores; the eight hundred stones that follow are grown from it on every load.
##
## The stage list, the class names, the file paths and the doc text are all read from the addon at
## runtime. Add a ninth stage to `GladeWallPipeline.STAGES` and this chapter grows a ninth step with
## no edit here.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Rig := preload("res://scripts/dev/atlas/atlas_rig.gd")

var atlas                                      ## the Atlas root, injected

var _step := 0                                 ## 0 = intent only; 1..n = after stage n-1
var _holder: Node3D
var _intent: Node3D
var _length := 8.0
var _storeys := 1
var _jetty := 0.0
var _weather := 0.0
var _mode := 0                                 ## 0 masonry, 1 timber, 2 adobe
var _verified := {}


func setup() -> void:
	_holder = Node3D.new()
	atlas.stage.add_child(_holder)
	_intent = Node3D.new()
	atlas.stage.add_child(_intent)
	_step = 0
	_rebuild()


func teardown() -> void:
	pass


func on_step(dir: int) -> void:
	var last: int = atlas.rig.stage_names.size()
	_step = clampi(_step + dir, 0, last)
	_render()
	atlas.refresh()


# ---------------------------------------------------------------- building --------------------


func _rebuild() -> void:
	var rig = atlas.rig
	rig.style_path = [Rig.STYLE_STONE, Rig.STYLE_TIMBER, Rig.STYLE_CLAY][_mode]
	rig.points = _plan()
	rig.wall_height = 2.6
	rig.weather = _weather
	rig.storeys = _make_storeys()
	rig.openings = []
	if not rig.build(_holder):
		atlas.set_badge("rig error: %s" % rig.error, false)
		return

	# THE ANTI-DRIFT CHECK, on every rebuild — see atlas.gd's header for why it is not optional.
	_verified = rig.verify_against_wall(atlas)
	if _verified.ok:
		atlas.set_badge("rig ✓ matches GladeWall (%d pieces)" % _verified.mine, true)
	else:
		atlas.set_badge("rig ✗ DIVERGED — %d vs %d. %s"
				% [_verified.mine, _verified.theirs, _verified.note], false)

	_step = mini(_step, rig.stage_names.size())
	_render()
	_draw_intent()


## A closed footprint with one bend, so corners, runs and the mitre all have something to do.
func _plan() -> Array:
	var w := _length
	return [Vector3.ZERO, Vector3(w, 0, 0), Vector3(w, 0, 5.0), Vector3(0, 0, 5.0), Vector3.ZERO]


func _make_storeys() -> Array:
	if _storeys <= 1:
		return []
	var out: Array = []
	for i in _storeys:
		var s := GladeStorey.new()
		s.height = 2.6 if i == 0 else 2.3
		s.jetty = 0.0 if i == 0 else _jetty
		out.append(s)
	return out


func _render() -> void:
	atlas.rig.render(_holder, _step - 1, true)
	_intent.visible = _step == 0


## The curve itself, drawn as a ribbon of line segments. This is the whole of what a scene file
## holds — worth seeing on its own before the stones arrive.
func _draw_intent() -> void:
	for c in _intent.get_children():
		c.queue_free()
	var rig = atlas.rig
	if rig.ctx == null:
		return
	var f := rig.ctx.frame as GladeWallFrame
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var pos := 0.0
	while pos < f.length:
		var a := f.plumb(pos)
		var b := f.plumb(minf(pos + 0.25, f.length))
		for h: float in [0.0, rig.ctx.stack.total_height()]:
			im.surface_add_vertex(a + Vector3.UP * h)
			im.surface_add_vertex(b + Vector3.UP * h)
		pos += 0.25
	# the uprights at each authored control point — the actual saved data
	for p in rig.points:
		var v: Vector3 = p
		im.surface_add_vertex(v)
		im.surface_add_vertex(v + Vector3.UP * rig.ctx.stack.total_height())
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = GladeDebug.overlay_material(Color(1.0, 0.85, 0.35))
	_intent.add_child(mi)


# ---------------------------------------------------------------- the panel -------------------


func build_rows(box: VBoxContainer) -> void:
	var rig = atlas.rig
	var last: int = rig.stage_names.size()

	var head := Label.new()
	if _step == 0:
		head.text = "step 0 / %d — INTENT ONLY" % last
	else:
		head.text = "step %d / %d — %s" % [_step, last, rig.stage_names[_step - 1]]
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)

	var stat := Label.new()
	stat.add_theme_font_size_override("font_size", 11)
	if _step == 0:
		stat.text = "the curve, the height and the markers.\nEverything else is regrown from these."
	else:
		stat.text = "+%d pieces · %.2f ms\ntotal so far: %d of %d" % [rig.placed_by(_step - 1),
				rig.stage_ms[_step - 1], _pieces_upto(_step - 1), rig.total_pieces()]
	box.add_child(stat)

	Tuning.button(box, "◀  previous", func(): on_step(-1))
	Tuning.button(box, "next  ▶", func(): on_step(1))

	# every stage as a jump button, so the list itself is the table of contents
	Tuning.header(box, "stages")
	for i in last:
		var mark := "▶ " if i == _step - 1 else "   "
		var b := Tuning.button(box, "%s%d %s  (%d)" % [mark, i + 1,
				rig.stage_names[i].replace("GladeStage", ""), rig.placed_by(i)],
				func(): _jump(i))
		b.add_theme_font_size_override("font_size", 11)

	Tuning.header(box, "intent")
	Tuning.slider(box, "length", 4.0, 16.0, 0.5, _length,
			func(v): _length = v; _rebuild(); atlas.refresh())
	Tuning.slider(box, "storeys", 1, 3, 1, _storeys,
			func(v): _storeys = int(v); _rebuild(); atlas.refresh())
	Tuning.slider(box, "jetty", 0.0, 0.4, 0.02, _jetty,
			func(v): _jetty = v; _rebuild(); atlas.refresh())
	Tuning.slider(box, "weather", 0.0, 1.0, 0.05, _weather,
			func(v): _weather = v; _rebuild(); atlas.refresh())

	Tuning.header(box, "fill mode")
	for i in 3:
		var names := ["masonry", "timber", "adobe"]
		var b := Tuning.button(box, ("▶ " if i == _mode else "   ") + names[i],
				func(): _mode = i; _rebuild(); atlas.refresh())
		b.add_theme_font_size_override("font_size", 11)

	# the reading pane follows the step
	if _step == 0:
		atlas.show_class("GladeWallPipeline")
	else:
		atlas.show_class(rig.stage_paths[_step - 1])


func _jump(i: int) -> void:
	_step = i + 1
	_render()
	atlas.refresh()


func _pieces_upto(stage_i: int) -> int:
	var n := 0
	for i in stage_i + 1:
		n += atlas.rig.placed_by(i)
	return n
