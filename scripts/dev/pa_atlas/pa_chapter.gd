extends RefCounted
## A CHAPTER IS A DEPTH OF THE RECURSION. Its focus is one cell of that level (a ward, a
## building, a room …), its steps are the operators of that cell's recipe, in the order the
## generator ran them: step 0 is the cell AS GIVEN by its parent (its outline, its entrances,
## its rules), step k is after operator k. The plan shows the tree as it was at that moment
## — earlier siblings finished, later ones bare, the focus warm — and the reading pane shows
## the operator's own doc header, its params with the rule names resolved, the rules in force
## and the program. `N`/`P` walk the cells of the level; a click on the plan drills down.

const Tuning := preload("res://scripts/dev/tuning_panel.gd")

var atlas                                      ## the PaAtlas root, injected
var level := 0                                 ## 0 zone … 5 areas
var focus: RefCounted                          ## the cell this chapter is on
var step := 0                                  ## 0 = as given; k = after operator k


func setup() -> void:
	var cells: Array = atlas.rig.cells_at(level)
	focus = null
	var wanted: RefCounted = atlas.wanted_focus
	if wanted != null and atlas.rig.level_of(wanted) == level:
		focus = wanted
	elif not cells.is_empty():
		focus = cells[0]
	step = 0
	atlas.wanted_focus = null


func teardown() -> void:
	pass


# ---------------------------------------------------------------- stepping -----------------


func steps() -> PackedInt32Array:
	if focus == null:
		return PackedInt32Array()
	return atlas.rig.steps(focus)


func last() -> int:
	return steps().size()


## The global step the plan is drawn at.
func global_step() -> int:
	if focus == null:
		return -1
	if step <= 0:
		return atlas.rig.birth(focus)
	var st := steps()
	return st[mini(step, st.size()) - 1]


func entry() -> Dictionary:
	if step <= 0:
		return {}
	return atlas.rig.entry(global_step())


func on_step(dir: int) -> void:
	step = clampi(step + dir, 0, last())
	atlas.refresh()


func jump(i: int) -> void:
	step = clampi(i + 1, 0, last())
	atlas.refresh()


func next_cell(dir: int) -> void:
	var cells: Array = atlas.rig.cells_at(level)
	if cells.is_empty():
		return
	var i := cells.find(focus)
	i = posmod(i + dir, cells.size()) if i >= 0 else 0
	focus = cells[i]
	step = 0
	atlas.refresh()
	atlas.frame_plan()


# ---------------------------------------------------------------- the panel ----------------


func build_rows(box: VBoxContainer) -> void:
	var rig = atlas.rig
	var cells: Array = rig.cells_at(level)
	if focus == null:
		Tuning.line(box, "no cell at this level in this zone (the officer wing has storeys only when it fits a stair)")
		return
	var n := last()
	var e := entry()
	# WRAPPED labels, or one long line widens the whole panel over the plan (tuning_panel.gd)
	var head: Label = Tuning.line(box, "step 0 / %d — AS GIVEN" % n if step == 0 else "step %d / %d — %s" % [step, n, String(e.op)], Color(1.0, 0.85, 0.4))
	head.add_theme_font_size_override("font_size", 14)
	var text := ""
	if step == 0:
		text = "%s\n%s · floor %d · depth %d · boundary %s%s" % [rig.cell_label(focus), focus.kind if focus.kind != "" else focus.role,
				int(focus.floor), int(focus.depth), String(focus.boundary), "" if bool(focus.floored) else " · region only"]
	else:
		var ch: PackedStringArray = e.changes
		text = "%s · %.2f ms" % [", ".join(ch) if not ch.is_empty() else "no change", float(e.ms)]
		if not (e.warnings as PackedStringArray).is_empty():
			text += "\n! %d warnings" % (e.warnings as PackedStringArray).size()
	var stat: Label = Tuning.line(box, text)
	stat.add_theme_font_size_override("font_size", 11)

	var row := HBoxContainer.new()
	box.add_child(row)
	for spec in [["◀ prev", -1], ["next ▶", 1]]:
		var b := Button.new()
		b.text = String(spec[0])
		var d := int(spec[1])
		b.pressed.connect(func() -> void: on_step(d))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	Tuning.button(box, "play / pause  [space]", func() -> void: atlas.toggle_play())

	# every operator of the recipe as a jump button — the list itself is the table of contents
	Tuning.header(box, "steps of %s" % focus.id)
	var st := steps()
	for i in st.size():
		var te: Dictionary = rig.entry(st[i])
		var mark := "▶ " if i == step - 1 else "   "
		var ch: PackedStringArray = te.changes
		var b := Tuning.button(box, "%s%d %s  %s" % [mark, i + 1, String(te.op), ch[0] if not ch.is_empty() else ""],
				func() -> void: jump(i))
		b.add_theme_font_size_override("font_size", 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true

	# the cells of this level: walk them, or pick one
	Tuning.header(box, "%s — %d of %d" % [atlas.rig.LEVELS[level].to_lower(), cells.find(focus) + 1, cells.size()])
	var crow := HBoxContainer.new()
	box.add_child(crow)
	for spec in [["◀ prev cell  [P]", -1], ["next cell ▶  [N]", 1]]:
		var b := Button.new()
		b.text = String(spec[0])
		var d := int(spec[1])
		b.pressed.connect(func() -> void: next_cell(d))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(b)
	if cells.size() <= 14:
		for c: RefCounted in cells:
			var b := Tuning.button(box, ("▶ " if c == focus else "   ") + "%s  %s  %.0f m²" % [c.token if c.token != "" else c.id, c.role, c.area()],
					func() -> void: atlas.drill(c))
			b.add_theme_font_size_override("font_size", 11)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
	if focus.parent != null:
		var ub := Tuning.button(box, "▲ up to %s  [Backspace]" % focus.parent.id, func() -> void: atlas.up())
		ub.clip_text = true
	var floors := _floors_below(focus)
	if floors.size() > 1:
		var frow := HBoxContainer.new()
		box.add_child(frow)
		for spec in [["floor −  [", -1], ["floor +  ]", 1]]:
			var b := Button.new()
			b.text = String(spec[0])
			var d := int(spec[1])
			b.pressed.connect(func() -> void: atlas.shift_floor(d))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			frow.add_child(b)
	Tuning.button(box, "bake at this step in 3D  [G]", func() -> void: atlas.bake_here())

	# the reading pane follows the step
	atlas.show_step(focus, e)


## The floors the focus's subtree lives on.
func _floors_below(c: RefCounted) -> Array:
	var f := {}
	for d: RefCounted in c.walk():
		f[int(d.floor)] = true
	var out: Array = f.keys()
	out.sort()
	return out
