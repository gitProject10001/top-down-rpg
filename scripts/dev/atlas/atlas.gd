extends Node3D
## GLADEKIT ATLAS — a scene for studying the system rather than using it.
##
## Six chapters, switched with 1-6. Everything is driven from OUTSIDE the addon: this scene reads
## GladeKit's public API and its source text, and adds nothing to `addons/gladekit/`. Delete this
## file, `scripts/dev/atlas/` and `scenes/dev/gladekit_atlas.tscn` and no trace of it remains.
##
##   1  PIPELINE   step the 8 stages; watch a wall assemble one rule at a time
##   2  MODULES    the dependency graph, derived from the source every time it opens
##   3  DOMAINS    arc x height made visible — why a bend is never a special case
##   4  FILLS      the same run built by all three strategies, side by side
##   5  JUNCTIONS  two buildings in the same place: rank, claim volumes, seams
##   6  MASSES     the other authoring primitive: a solid, its faces, and the wireframe of both
##                 kinds of triangle it commits. Companion doc: `docs/gladekit-masses.md`
##
##   left/right  step        R  reset        F  frame        Tab  hide the panel
##   RMB + WASD  fly (scripts/dev/fly_camera.gd)
##
## DELIBERATELY NO `class_name`, like the rest of scripts/dev — see tuning_panel.gd for the reason
## (an editor rescan once corrupted a tuned style .tres). The scene attaches this by path.
##
## THE BADGE AT THE TOP OF THE PANEL IS THE POINT. `atlas_rig.gd` is a second driver of the same
## pipeline, so it could drift into a plausible lie. On every rebuild the atlas also builds a real
## `GladeWall` from the same intent and compares placements; if they ever disagree the badge goes
## red and says so. An explainer that can quietly become wrong is worse than none.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Rig := preload("res://scripts/dev/atlas/atlas_rig.gd")
const Source := preload("res://scripts/dev/atlas/atlas_source.gd")

const ChapterPipeline := preload("res://scripts/dev/atlas/chapter_pipeline.gd")
const ChapterModules := preload("res://scripts/dev/atlas/chapter_modules.gd")
const ChapterDomains := preload("res://scripts/dev/atlas/chapter_domains.gd")
const ChapterFills := preload("res://scripts/dev/atlas/chapter_fills.gd")
const ChapterJunctions := preload("res://scripts/dev/atlas/chapter_junctions.gd")
const ChapterMasses := preload("res://scripts/dev/atlas/chapter_masses.gd")

const PANEL_W := 330
const DOC_W := 400

const CHAPTERS := ["Pipeline", "Modules", "Domains", "Fill strategies", "Junctions", "Masses"]

var rig                                        ## the shared AtlasRig
var stage: Node3D                              ## where chapters put their 3D content
var camera: Camera3D

var _chapter := 0
var _chapters: Array = []
var _box: VBoxContainer
var _layer: CanvasLayer
var _badge: Label
var _title: Label
var _doc: Label
var _panel_visible := true


func _ready() -> void:
	rig = Rig.new()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	camera = get_node_or_null("FlyCamera") as Camera3D

	_chapters = [ChapterPipeline.new(), ChapterModules.new(), ChapterDomains.new(),
			ChapterFills.new(), ChapterJunctions.new(), ChapterMasses.new()]
	for c in _chapters:
		c.atlas = self

	_build_panel()
	_enter(0)


# ---------------------------------------------------------------- chapters -------------------


func _enter(i: int) -> void:
	if _chapter < _chapters.size() and _chapters[_chapter].has_method("teardown"):
		_chapters[_chapter].teardown()
	for ch in stage.get_children():
		ch.queue_free()
	_chapter = clampi(i, 0, _chapters.size() - 1)
	_chapters[_chapter].setup()
	refresh()


## Rebuild the panel and let the chapter redraw. Chapters call this after any knob moves.
func refresh() -> void:
	var c = _chapters[_chapter]
	_title.text = "%d/%d  %s" % [_chapter + 1, CHAPTERS.size(), CHAPTERS[_chapter]]
	_clear_rows()
	if c.has_method("build_rows"):
		c.build_rows(_rows)


## Put a class's own doc header in the reading pane. This is why the atlas cannot go stale: the text
## comes out of the .gd file at runtime, so editing the code edits the explanation.
func show_class(cls_or_path: String) -> void:
	var d: Dictionary = Source.read(cls_or_path) if cls_or_path.begins_with("res://") \
			else Source.for_class(cls_or_path)
	var path := cls_or_path if cls_or_path.begins_with("res://") else Source.path_of(cls_or_path)
	_doc.text = "%s\n%s · %d lines\n\n%s" % [d.name,
			path.replace("res://addons/gladekit/", ""), d.lines, Source.wrap(d.doc, 54)]


## The anti-drift badge. `ok` false paints it red and keeps the reason on screen.
func set_badge(text: String, ok: bool) -> void:
	_badge.text = text
	_badge.add_theme_color_override("font_color",
			Color(0.55, 0.95, 0.6) if ok else Color(1.0, 0.45, 0.4))


# ---------------------------------------------------------------- input ----------------------


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_6:
		_enter(k - KEY_1)
		get_viewport().set_input_as_handled()
	elif k == KEY_LEFT or k == KEY_RIGHT:
		var c = _chapters[_chapter]
		if c.has_method("on_step"):
			c.on_step(1 if k == KEY_RIGHT else -1)
		get_viewport().set_input_as_handled()
	elif k == KEY_R:
		_enter(_chapter)
	elif k == KEY_F:
		_frame_stage()
	elif k == KEY_TAB:
		_panel_visible = not _panel_visible
		_layer.visible = _panel_visible
		_doc_layer.visible = _panel_visible
		get_viewport().set_input_as_handled()


## Pull the camera back to see whatever the chapter just built.
func _frame_stage() -> void:
	if camera == null:
		return
	var aabb := AABB()
	var first := true
	for n in stage.get_children():
		if n is VisualInstance3D:
			var b: AABB = (n as VisualInstance3D).get_aabb()
			b.position += (n as Node3D).global_position
			aabb = b if first else aabb.merge(b)
			first = false
	if first:
		return
	var c := aabb.get_center()
	var r := maxf(aabb.size.length() * 0.6, 4.0)
	camera.global_position = c + Vector3(0.35, 0.55, 1.0).normalized() * r
	camera.look_at(c, Vector3.UP)


# ---------------------------------------------------------------- the panel -------------------


func _build_panel() -> void:
	_box = Tuning.build_panel(self, PANEL_W, 660)
	_layer = _box.get_parent().get_parent().get_parent() as CanvasLayer

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_box.add_child(_title)
	_box.move_child(_title, 0)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 11)
	_box.add_child(_badge)
	_box.move_child(_badge, 1)

	var keys := Label.new()
	keys.text = "1-6 chapter · ←/→ step · R reset\nF frame · Tab panel · RMB+WASD fly"
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	_box.add_child(keys)
	_box.move_child(keys, 2)

	# A CHAPTER OWNS ITS OWN CONTAINER, so switching chapters is one `free the children` rather than
	# index arithmetic over a mixed list.
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_box.add_child(_rows)

	_build_doc_panel()


## THE READING PANE GETS ITS OWN PANEL, on the right.
##
## It began at the bottom of the left column and that was wrong twice over: in the Pipeline chapter
## the stage list pushed it below the fold, so the thing the atlas is FOR was the one thing you
## could not see; and its long lines widened the whole column until it covered the module map.
## Controls left, reading right, the subject in between.
func _build_doc_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	_doc_layer = layer

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -DOC_W - 12
	panel.offset_right = -12
	panel.offset_top = 12
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DOC_W - 10, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_doc = Label.new()
	_doc.custom_minimum_size = Vector2(DOC_W - 26, 0)
	_doc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_doc.add_theme_font_size_override("font_size", 11)
	_doc.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	scroll.add_child(_doc)


var _rows: VBoxContainer
var _doc_layer: CanvasLayer


func _clear_rows() -> void:
	for n in _rows.get_children():
		_rows.remove_child(n)
		n.queue_free()
