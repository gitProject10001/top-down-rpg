extends Node3D
## PA ATLAS — a scene for studying the procedural-architecture generator step by step, AT EVERY
## DEPTH OF ITS RECURSION. The GladeKit atlas's shell (chapters, a step list that is its own table
## of contents, the operator's own doc header in a reading pane, an honesty badge, a 3D stage)
## with the layout lab's plan drawing and tuning sliders, adapted to the ladder:
##
##   1  ZONE       the area: outline, entrance, the rules of scale; the program of wards, the
##                 Poisson seeds, the Voronoi partition and its frame walls, the connect graph
##   2  WARDS      one ward at a time: its buildings grown apart by the passage, the cave, the
##                 ritual hall; N/P walk the wards, a click on the plan drills into one
##   3  BUILDINGS  a building: its storeys and stair, or its rooms grown from the hall at the door
##   4  STOREYS    a floor of a building
##   5  ROOMS      a room: its activity areas, its dressing
##   6  AREAS      an area's dressing at the metre
##   7  BAKE       the plan at that step through the drafter and the floorplan façade, in 3D,
##                 with a 1.8 m capsule at the entrance for scale
##
## Every chapter steps ONE CELL's recipe: step 0 is the cell as its parent gave it, step k is
## after operator k — the plan shows the tree as it was at that moment (the generator's trace
## stamps everything it makes with its step; nothing is rebuilt, only filtered), the reading
## pane shows the operator's own `##` header, its params with rule names resolved, the rules in
## force and where they were set, the program, the step's warnings.
##
##   1-7 chapter · ←/→ step · N/P cell · click drill down · Backspace up · space play
##   R reroll · Shift+R reset rules · F frame · G bake here · Tab panels · [ ] floor
##   RMB + WASD fly in the bake (scripts/dev/fly_camera.gd)
##
## Everything is driven from OUTSIDE the addon through its public pieces (Generator, ZoneBrief,
## the drafter, the floorplan façade). Deliberately no `class_name` (scripts/dev's rule, see
## tuning_panel.gd). Headless proof: `-- --selftest=<dir>`.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")
const Source := preload("res://scripts/dev/atlas/atlas_source.gd")
const Rig := preload("res://scripts/dev/pa_atlas/pa_rig.gd")
const Chapter := preload("res://scripts/dev/pa_atlas/pa_chapter.gd")
const ChapterBake := preload("res://scripts/dev/pa_atlas/pa_chapter_bake.gd")
const PlanView := preload("res://scripts/dev/pa_atlas/pa_plan_view.gd")
const Dungeon := preload("res://addons/procedural_architecture/gen/recipes/dungeon.gd")

const PANEL_W := 330
const DOC_W := 400
const CHAPTERS := ["Zone", "Wards", "Buildings", "Storeys", "Rooms", "Areas", "Bake"]
const RULE_KEYS := ["passage_m", "door_m", "min_rooms", "fill_ward"]

var rig                                        ## the PaRig
var stage: Node3D                              ## the 3D content of the bake chapter
var camera: Camera3D
var wanted_focus: RefCounted                   ## a drill-down's target, read by the chapter's setup
var bake_upto := -1                            ## G's step, read by the bake chapter

var _chapter := 0
var _chapters: Array = []
var _box: VBoxContainer
var _layer: CanvasLayer
var _doc_layer: CanvasLayer
var _plan_layer: CanvasLayer
var _plan: Control
var _rows: VBoxContainer
var _globals: VBoxContainer
var _title: Label
var _badge: Label
var _doc: Label
var _stats_line: Label
var _panel_visible := true
var _playing := false
var _speed := 0.6
var _clock := 0.0
var _floor_shift := 0
var _debounce: Timer
var _rules := {}                               ## the sliders' values (the brief's rules)
var _selftest_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--selftest="):
			_selftest_dir = a.trim_prefix("--selftest=")
	# room for three columns: the panel, the plan, the reading pane
	if DisplayServer.window_get_size().x < 1500:
		DisplayServer.window_set_size(Vector2i(1600, 950))
	rig = Rig.new(self)
	_rules = Dungeon.RULES.duplicate(true)
	rig.rebuild()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	camera = get_node_or_null("FlyCamera") as Camera3D
	_build_plan_layer()
	_chapters = []
	for i in 6:
		var c = Chapter.new()
		c.atlas = self
		c.level = i
		_chapters.append(c)
	var bake = ChapterBake.new()
	bake.atlas = self
	_chapters.append(bake)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.3
	_debounce.timeout.connect(_regenerate)
	add_child(_debounce)
	_build_panel()
	_build_globals()
	_enter(0)
	if _selftest_dir != "":
		_selftest(_selftest_dir)


# ---------------------------------------------------------------- chapters -------------------


func _enter(i: int) -> void:
	if _chapter < _chapters.size() and _chapters[_chapter].has_method("teardown"):
		_chapters[_chapter].teardown()
	for ch in stage.get_children():
		ch.queue_free()
	_chapter = clampi(i, 0, _chapters.size() - 1)
	_playing = false
	_floor_shift = 0
	_chapters[_chapter].setup()
	_plan_layer.visible = not _is_bake()
	refresh()
	frame_plan()


func _is_bake() -> bool:
	return _chapter == _chapters.size() - 1


func chapter():
	return _chapters[_chapter]


## The cell the plan is about (null in the bake).
func focus() -> RefCounted:
	var c = chapter()
	return c.focus if "focus" in c else null


## The global step the plan is drawn at.
func step_global() -> int:
	var c = chapter()
	if c.has_method("global_step"):
		return c.global_step()
	return rig.trace.size() - 1


func floor_shown() -> int:
	var f: RefCounted = focus()
	return (int(f.floor) if f != null else 0) + _floor_shift


func shift_floor(d: int) -> void:
	_floor_shift += d
	refresh()


## Rebuild the chapter's rows and redraw; the globals (seed, size, rules) stay as they are.
func refresh() -> void:
	var c = chapter()
	var f: RefCounted = focus()
	var what := " — %s" % rig.cell_label(f) if f != null and not _is_bake() else ""
	_title.text = "%d/%d  %s%s" % [_chapter + 1, CHAPTERS.size(), CHAPTERS[_chapter], what]
	if rig.verified.ok:
		set_badge("trace ✓ matches Generator (%d cells, %d rooms, %.0f ms)" % [int(rig.stats.cells), int(rig.stats.rooms), rig.gen_ms], true)
	else:
		set_badge("trace ✗ DIVERGED — %s" % String(rig.verified.note), false)
	_clear_rows()
	if c.has_method("build_rows"):
		c.build_rows(_rows)
	if _stats_line != null:
		_stats_line.text = "%d wards · %d buildings · %d rooms · %d gates · %d fixtures · gen %.0f ms · %d warnings" % [
				int(rig.stats.wards), int(rig.stats.buildings), int(rig.stats.rooms), int(rig.stats.gates), int(rig.stats.fixtures),
				rig.gen_ms, rig.warnings.size()]
	_plan.queue_redraw()


## Drill into a cell: its level's chapter, with it in focus.
func drill(cell: RefCounted) -> void:
	var lv: int = rig.level_of(cell)
	if lv < 0:
		return
	wanted_focus = cell
	_enter(lv)


func up() -> void:
	var f: RefCounted = focus()
	if f != null and f.parent != null:
		drill(f.parent)


## The deepest focusable cell under a point of the plan, at the step shown.
func pick_at(p: Vector2) -> void:
	if _is_bake():
		return
	var s := step_global()
	var fl := floor_shown()
	var best: RefCounted = null
	for c: RefCounted in rig.tree.walk():
		if rig.level_of(c) < 0 or not _plan.visible_at(c, s, fl):
			continue
		if Geometry2D.is_point_in_polygon(p, rig.polygon_at(c, s)):
			if best == null or int(c.depth) >= int(best.depth):
				best = c
	if best != null:
		drill(best)


func toggle_play() -> void:
	var c = chapter()
	if not c.has_method("on_step") or _is_bake():
		return
	if not _playing and c.step >= c.last():
		c.step = 0
	_playing = not _playing
	_clock = 0.0
	refresh()


func _process(delta: float) -> void:
	if not _playing:
		return
	_clock += delta
	if _clock < _speed:
		return
	_clock = 0.0
	var c = chapter()
	if c.step >= c.last():
		_playing = false
		refresh()
		return
	c.on_step(1)


## G: the bake chapter with this chapter's step.
func bake_here() -> void:
	bake_upto = step_global() if not _is_bake() else -1
	_enter(_chapters.size() - 1)


# ---------------------------------------------------------------- the plan layer ------------


func _build_plan_layer() -> void:
	_plan_layer = CanvasLayer.new()
	_plan_layer.layer = 30
	add_child(_plan_layer)
	_plan = PlanView.new()
	_plan.atlas = self
	_plan.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plan_layer.add_child(_plan)


## The plan's room between the two panels (the panels' REAL widths: a label can widen one).
func plot_rect() -> Rect2:
	var sz := _plan.size
	var panel := _box.get_parent().get_parent() as Control
	var l := (panel.size.x + 24.0 if panel != null else float(PANEL_W + 24)) if _panel_visible else 12.0
	var r := float(DOC_W + 24) if _panel_visible else 12.0
	return Rect2(l, 12.0, maxf(sz.x - l - r, 100.0), maxf(sz.y - 24.0, 100.0))


## Fit the plan to the focus (the whole zone in chapter 1).
func frame_plan() -> void:
	if _is_bake():
		return
	var f: RefCounted = focus()
	if f == null:
		f = rig.tree
	var box: Rect2 = f.bbox()
	if f.parent != null:
		box = box.grow(maxf(box.size.x, box.size.y) * 0.15)
	_plan.fit(box, plot_rect())


func hud_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var c = chapter()
	var f: RefCounted = focus()
	if f == null:
		return out
	var e: Dictionary = c.entry()
	if e.is_empty():
		out.append("%s · step 0 / %d · as given" % [f.id, c.last()])
	else:
		out.append("%s · step %d / %d · %s · %.1f ms" % [f.id, c.step, c.last(), String(e.op), float(e.ms)])
		for w in e.warnings:
			out.append("! " + String(w))
	out.append("global step %d of %d · floor %d · %s" % [step_global(), rig.trace.size(), floor_shown(), "PLAYING" if _playing else ""])
	return out


# ---------------------------------------------------------------- the reading pane ----------


## The operator's own header, then what it was given and what it read.
func show_step(cell: RefCounted, e: Dictionary) -> void:
	var lines := PackedStringArray()
	if e.is_empty():
		var d: Dictionary = Source.read("res://addons/procedural_architecture/gen/recipes/dungeon.gd")
		lines.append("THE CELL AS GIVEN — %s" % cell.id)
		lines.append("role %s · kind %s · depth %d · floor %d · %.0f m²" % [cell.role, cell.kind, int(cell.depth), int(cell.floor), cell.area()])
		lines.append("boundary %s · %s" % [String(cell.boundary), "floored" if bool(cell.floored) else "region only"])
		lines.append("")
		lines.append("recipe: " + ", ".join(_recipe_ops(cell)))
		lines.append("")
		lines.append(Source.wrap(d.doc, 54))
	else:
		var d: Dictionary = Source.read(rig.op_path(String(e.op)))
		lines.append("%s · %s" % [String(e.op).to_upper(), String(rig.op_path(String(e.op))).replace("res://addons/procedural_architecture/", "")])
		lines.append("")
		lines.append(Source.wrap(d.doc, 54))
		lines.append("")
		lines.append("params:")
		var params: Dictionary = e.params
		for key in params:
			var v: Variant = params[key]
			if v is Array and not (v as Array).is_empty() and (v as Array)[0] is Dictionary:
				lines.append("  %s: %d entries" % [key, (v as Array).size()])
				for item: Dictionary in v:
					lines.append("    %s" % _short(item))
			elif v is Dictionary:
				lines.append("  %s: %s" % [key, _short(v)])
			else:
				lines.append("  %s = %s" % [key, rig.resolve_param(cell, v)])
		if not (e.changes as PackedStringArray).is_empty():
			lines.append("")
			lines.append("did: " + ", ".join(e.changes))
		if not (e.warnings as PackedStringArray).is_empty():
			lines.append("")
			lines.append("warnings:")
			for w in e.warnings:
				lines.append("  ! " + String(w))
	lines.append("")
	lines.append("rules in force:")
	for r: Dictionary in rig.rules_in_effect(cell):
		lines.append("  %s = %s   (%s%s)" % [r.key, str(r.value), String(r.by), " @ %d" % int(r.step) if int(r.step) >= 0 else ""])
	if not (cell.program as Array).is_empty():
		lines.append("")
		lines.append("program:")
		for item: Dictionary in cell.program:
			lines.append("  " + _short(item))
	_doc.text = "\n".join(lines)


func show_text(title: String, path: String, text: String) -> void:
	var d: Dictionary = Source.read(path)
	_doc.text = "%s\n%s\n\n%s\n\n%s" % [title, path.replace("res://addons/procedural_architecture/", ""), Source.wrap(text, 54), Source.wrap(d.doc, 54)]


func _recipe_ops(cell: RefCounted) -> PackedStringArray:
	var out := PackedStringArray()
	for st: Dictionary in Dungeon.for_role(String(cell.role), rig.brief):
		out.append(String(st.op))
	return out


func _short(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in d:
		var v: Variant = d[key]
		if v is float:
			parts.append("%s %.2f" % [key, float(v)])
		elif v is Array:
			parts.append("%s %s" % [key, str(v)])
		else:
			parts.append("%s %s" % [key, str(v)])
	return ", ".join(parts)


func set_badge(text: String, ok: bool) -> void:
	_badge.text = text
	_badge.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if ok else Color(1.0, 0.45, 0.4))


# ---------------------------------------------------------------- generate + rules -----------


func _regenerate() -> void:
	var keep := ""
	var f: RefCounted = focus()
	if f != null:
		keep = String(f.id)
	rig.brief.rules = _rules.duplicate(true)
	rig.rebuild()
	if keep != "":
		var again: RefCounted = rig.tree.find(keep)
		if again != null and rig.level_of(again) == _chapter:
			wanted_focus = again
	_enter(_chapter)


func _reroll(d: int) -> void:
	rig.brief.seed = int(rig.brief.seed) + d
	_regenerate()


func _build_globals() -> void:
	_globals = VBoxContainer.new()
	_globals.add_theme_constant_override("separation", 3)
	_box.add_child(_globals)
	Tuning.header(_globals, "generate")
	_stats_line = Tuning.line(_globals, "")
	var row := HBoxContainer.new()
	_globals.add_child(row)
	for spec in [["◀ seed", -1], ["seed ▶", 1]]:
		var b := Button.new()
		b.text = String(spec[0])
		var d := int(spec[1])
		b.pressed.connect(func() -> void: _reroll(d))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	Tuning.number(_globals, "seed", float(rig.brief.seed), 1.0, func(v: float) -> void:
		rig.brief.seed = int(v)
		_debounce.start())
	Tuning.slider(_globals, "size_m", 40.0, 300.0, 10.0, float(rig.brief.size_m), func(v: float) -> void:
		rig.brief.size_m = v
		_debounce.start())
	Tuning.check(_globals, "verify (the badge's second run)", rig.verify, func(on: bool) -> void:
		rig.verify = on
		_debounce.start())

	Tuning.header(_globals, "rules of scale")
	_rule_slider("passage_m", 1.0, 8.0, 0.25)
	_range_slider("building_m2", 0, 50.0, 500.0, 10.0, "building min m²")
	_range_slider("building_m2", 1, 200.0, 1500.0, 25.0, "building max m²")
	_range_slider("room_m2", 0, 9.0, 60.0, 1.0, "room min m²")
	_range_slider("room_m2", 1, 40.0, 200.0, 5.0, "room max m²")
	_rule_slider("min_rooms", 1.0, 10.0, 1.0)
	_rule_slider("fill_ward", 0.3, 0.9, 0.05)
	_rule_slider("door_m", 0.8, 2.4, 0.1)
	Tuning.button(_globals, "reset rules to the recipe's  [Shift+R]", func() -> void: _reset_rules())


func _rule_slider(key: String, lo: float, hi: float, step: float) -> void:
	Tuning.slider(_globals, key, lo, hi, step, float(_rules.get(key, lo)), func(v: float) -> void:
		_rules[key] = int(v) if key == "min_rooms" else v
		_debounce.start())


func _range_slider(key: String, idx: int, lo: float, hi: float, step: float, label: String) -> void:
	var cur: Array = _rules.get(key, [lo, hi])
	Tuning.slider(_globals, label, lo, hi, step, float(cur[idx]), func(v: float) -> void:
		var r: Array = (_rules.get(key, [lo, hi]) as Array).duplicate()
		r[idx] = v
		if idx == 0 and float(r[1]) < v:
			r[1] = v
		if idx == 1 and float(r[0]) > v:
			r[0] = v
		_rules[key] = r
		_debounce.start())


func _reset_rules() -> void:
	_rules = Dungeon.RULES.duplicate(true)
	_globals.queue_free()
	_build_globals()
	_regenerate()


# ---------------------------------------------------------------- input ----------------------


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var ke := e as InputEventKey
	var k := ke.keycode
	if k >= KEY_1 and k <= KEY_7:
		_enter(k - KEY_1)
	elif k == KEY_LEFT or k == KEY_RIGHT:
		var c = chapter()
		if c.has_method("on_step"):
			c.on_step(1 if k == KEY_RIGHT else -1)
	elif k == KEY_N or k == KEY_P:
		var c = chapter()
		if c.has_method("next_cell"):
			c.next_cell(1 if k == KEY_N else -1)
	elif k == KEY_BACKSPACE:
		up()
	elif k == KEY_SPACE:
		toggle_play()
	elif k == KEY_R:
		if ke.shift_pressed:
			_reset_rules()
		else:
			_reroll(1)
	elif k == KEY_F:
		if _is_bake():
			_frame_stage()
		else:
			frame_plan()
	elif k == KEY_G:
		bake_here()
	elif k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT:
		shift_floor(1 if k == KEY_BRACKETRIGHT else -1)
	elif k == KEY_TAB:
		_panel_visible = not _panel_visible
		_layer.visible = _panel_visible
		_doc_layer.visible = _panel_visible
		frame_plan()
	else:
		return
	get_viewport().set_input_as_handled()


## The camera over a point of the plan, looking down into it.
func frame_at(p: Vector3) -> void:
	if camera == null:
		return
	camera.global_position = p + Vector3(-14.0, 16.0, 14.0)
	camera.look_at(p + Vector3(0, 1.0, 0), Vector3.UP)


func _frame_stage() -> void:
	if camera == null:
		return
	var aabb := AABB()
	var first := true
	for n in stage.get_children():
		for v in n.find_children("*", "VisualInstance3D", true, false):
			var b: AABB = (v as VisualInstance3D).get_aabb()
			b.position += (v as Node3D).global_position
			aabb = b if first else aabb.merge(b)
			first = false
	if first:
		return
	var c := aabb.get_center()
	var r := maxf(aabb.size.length() * 0.6, 4.0)
	camera.global_position = c + Vector3(0.35, 0.55, 1.0).normalized() * r
	camera.look_at(c, Vector3.UP)


# ---------------------------------------------------------------- the panels -----------------


func _build_panel() -> void:
	_box = Tuning.build_panel(self, PANEL_W, 900)
	_layer = _box.get_parent().get_parent().get_parent() as CanvasLayer

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	_box.add_child(_title)
	_box.move_child(_title, 0)

	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 11)
	_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_badge.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	_box.add_child(_badge)
	_box.move_child(_badge, 1)

	var keys := Label.new()
	keys.text = "1-7 chapter · ←/→ step · N/P cell · click drill · Backspace up\nspace play · R reroll · F frame · G bake · Tab panels · [ ] floor"
	keys.add_theme_font_size_override("font_size", 10)
	keys.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	_box.add_child(keys)
	_box.move_child(keys, 2)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_box.add_child(_rows)
	_build_doc_panel()


func _build_doc_panel() -> void:
	_doc_layer = CanvasLayer.new()
	_doc_layer.layer = 41
	add_child(_doc_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -DOC_W - 12
	panel.offset_right = -12
	panel.offset_top = 12
	_doc_layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DOC_W - 10, 900)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_doc = Label.new()
	_doc.custom_minimum_size = Vector2(DOC_W - 26, 0)
	_doc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_doc.add_theme_font_size_override("font_size", 11)
	_doc.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	scroll.add_child(_doc)


func _clear_rows() -> void:
	for n in _rows.get_children():
		_rows.remove_child(n)
		n.queue_free()


# ---------------------------------------------------------------- selftest -------------------
## `-- --selftest=<dir>`: a windowed run that proves the atlas without a person — the trace
## ascends and resolves, what is visible only ever grows along a cell's steps, the last step of
## the zone shows every ward and gate, the badge is green, a click drills zone → ward →
## building, the brief's rules win, the bake stands; four pictures.


func _selftest(out_dir: String) -> void:
	var fails := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _wait(3)
	frame_plan()
	await _wait(1)
	var trace: Array = rig.trace
	if trace.is_empty():
		fails.append("no trace")
	var asc := true
	for i in trace.size():
		if int((trace[i] as Dictionary).step) != i or rig.tree.find(String((trace[i] as Dictionary).cell_id)) == null:
			asc = false
	if not asc:
		fails.append("trace steps not ascending or unresolved")
	if not rig.verified.ok:
		fails.append("badge red: " + String(rig.verified.note))
	# chapter 1: counts only grow along the zone's steps; the last step shows every ward and gate
	_enter(0)
	var c = chapter()
	var prev := {}
	for s in c.last() + 1:
		c.step = s
		var n: Dictionary = _plan.count_visible(step_global(), 0)
		for key in n:
			if prev.has(key) and int(n[key]) < int(prev[key]):
				fails.append("chapter 1 step %d: %s shrank" % [s, key])
		prev = n
	c.step = c.last()
	refresh()
	var wards: int = rig.tree.children.size()
	if int(prev.cells) != wards + 1 or int(prev.gates) != (rig.tree.gates as Array).size():
		fails.append("chapter 1 last step: %d cells (want %d), %d gates (want %d)" % [int(prev.cells), wards + 1, int(prev.gates), (rig.tree.gates as Array).size()])
	await _shot(out_dir + "/pa_atlas_zone.png", "res://scenes/dev/procedural_architecture/renders/pa_atlas_zone.png")
	# drill by clicks: a ward, then a building, then a room
	var ward: RefCounted = null
	for w: RefCounted in rig.tree.children:
		if rig.cells_at(2).any(func(b: RefCounted) -> bool: return b.parent == w):
			ward = w
			break
	if ward == null:
		fails.append("no ward with buildings")
	else:
		frame_plan()
		await _wait(1)
		await _click(ward.centroid())
		if _chapter != 1 or focus() != ward:
			fails.append("clicking a ward did not open chapter 2 on it (chapter %d)" % (_chapter + 1))
		c = chapter()
		c.step = c.last()
		refresh()
		await _shot(out_dir + "/pa_atlas_ward.png", "res://scenes/dev/procedural_architecture/renders/pa_atlas_ward.png")
		var building: RefCounted = null
		for b: RefCounted in ward.children:
			if b.is_building():
				building = b
				break
		await _wait(1)
		await _click(building.centroid())
		if _chapter != 2 or focus() != building:
			fails.append("clicking a building did not open chapter 3 on it (chapter %d)" % (_chapter + 1))
		c = chapter()
		c.step = c.last()
		refresh()
		await _shot(out_dir + "/pa_atlas_building.png", "res://scenes/dev/procedural_architecture/renders/pa_atlas_building.png")
		var room: RefCounted = null
		for r: RefCounted in building.walk():
			if rig.level_of(r) == 4:
				room = r
				break
		if room != null:
			drill(room)
			if _chapter != 4:
				fails.append("drilling a room opened chapter %d" % (_chapter + 1))
			up()
			if focus() != room.parent:
				fails.append("up did not return to the parent")
	# the brief's rules win
	_rules["passage_m"] = 3.0
	_regenerate()
	if not is_equal_approx(float(rig.tree.rule("passage_m", 0.0)), 3.0) or String(rig.tree.rule("style", "")) != "dungeon":
		fails.append("the brief's rules did not win")
	if not rig.verified.ok:
		fails.append("badge red after the rules change: " + String(rig.verified.note))
	# the bake
	bake_upto = -1
	_enter(_chapters.size() - 1)
	await _wait(2)
	var built := 0
	for n in stage.get_children():
		built += n.get_child_count()
	if built == 0:
		fails.append("the bake stands empty")
	_frame_stage()
	await _shot(out_dir + "/pa_atlas_bake.png", "res://scenes/dev/procedural_architecture/renders/pa_atlas_bake.png")
	for f in fails:
		print("[PaAtlas] FAIL: " + f)
	print("[PaAtlas] selftest: %d failures, %d trace steps, %d cells, output in %s" % [fails.size(), trace.size(), int(rig.stats.cells), out_dir])
	get_tree().quit(1 if not fails.is_empty() else 0)


func _click(at_m: Vector2) -> void:
	var px: Vector2 = _plan.to_px(at_m)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = px
		ev.global_position = px
		Input.parse_input_event(ev)
		await _wait(1)
	await _wait(1)


func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(path: String, also: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	if also != "":
		img.save_png(also)
