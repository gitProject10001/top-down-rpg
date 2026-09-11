extends Object
## The slider/colour/checkbox plumbing behind the look-development panels, in one place.
##
## Lifted verbatim out of scripts/dev/lookdev.gd when scripts/dev/whinbek_lookdev.gd needed the same
## widgets — two copies of forty lines of UI boilerplate is exactly how they drift apart, and a
## tuning panel whose slider does not read back the same way as the other one is worse than no panel.
##
## DELIBERATELY NO `class_name`. Registering a new global class requires an editor rescan, and a
## rescan is what re-saved and corrupted addons/gladekit/styles/crypt_stone.tres last cycle — a
## `@tool` script had just gained new `@export`s, and the editor wrote the stale in-memory resource
## back over the tuned one. Consumers `preload()` this file by path instead; nothing has to be
## registered and the editor never has to run.
##
## Every builder takes the container and a Callable, and returns nothing: the caller owns the state,
## this file owns only the widgets.


## The scaffold every panel sits in: a CanvasLayer above the 3D, a scrolling column on the left.
## Returns the VBox to add rows to.
static func build_panel(host: Node, width := 310, height := 620) -> VBoxContainer:
	var layer := CanvasLayer.new()
	layer.layer = 40
	host.add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.custom_minimum_size = Vector2(width, 0)
	# OPAQUE, because the default panel style is semi-transparent and the game's own HUD sits at
	# layer 20 — the crypt tuner's first screenshot had health hearts showing through the middle of
	# the shader sliders. A tuning value you have to squint past a heart to read is a misread value.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	bg.content_margin_left = 8
	bg.content_margin_right = 8
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width - 10, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width - 24, 0)
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)

	# ---- A GRIP, so the panel is not the size somebody guessed once.
	#
	# These panels are built in code with a width and a height baked in at the call site, and every
	# bench that grows a section eventually has a panel covering the thing it exists to look at.
	# The SWE lab reached that point twice in one afternoon: six new uniforms in the "no knob yet"
	# line widened it over half the 3D view, and the screenshot probe reported the water it could no
	# longer see as "full and empty look the same".
	#
	# A drag handle in the corner is eight lines and removes the whole class. The panel keeps a
	# minimum so it cannot be shrunk to nothing and lost.
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(0, 12)
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "drag to resize"
	panel.get_parent().add_child(grip)
	grip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var state := {"drag": false, "from": Vector2.ZERO, "size": Vector2(width, height)}
	grip.draw.connect(func() -> void:
		# Three ticks, the usual grip idiom, drawn rather than textured so it needs no asset.
		for i in 3:
			var o := float(i) * 4.0
			grip.draw_line(Vector2(2.0 + o, 10.0), Vector2(10.0, 2.0 + o),
					Color(0.55, 0.58, 0.66), 1.0))
	grip.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			state["drag"] = mb.pressed
			state["from"] = grip.get_global_mouse_position()
			state["size"] = Vector2(scroll.custom_minimum_size.x, scroll.custom_minimum_size.y)
			grip.accept_event()
			return
		var mm := ev as InputEventMouseMotion
		if mm != null and bool(state["drag"]):
			var d: Vector2 = grip.get_global_mouse_position() - (state["from"] as Vector2)
			var sz: Vector2 = (state["size"] as Vector2) + d
			# A floor, not a clamp to the viewport: a panel dragged off the bottom of a small
			# window is recoverable, a panel dragged to zero is gone.
			sz.x = maxf(sz.x, 180.0)
			sz.y = maxf(sz.y, 120.0)
			scroll.custom_minimum_size = sz
			panel.custom_minimum_size = Vector2(sz.x + 10.0, 0.0)
			box.custom_minimum_size = Vector2(sz.x - 14.0, 0.0)
			grip.accept_event())
	# Follow the panel's bottom-right corner wherever it ends up.
	panel.resized.connect(func() -> void:
		grip.position = panel.position + panel.size - Vector2(14.0, 14.0)
		grip.size = Vector2(12, 12)
		grip.queue_redraw())
	return box


static func header(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "\n" + text
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	box.add_child(l)


## A labelled slider whose label shows the live value — reading a number off a bare handle position
## is guesswork, and every tuning decision here is a number you will want to type into a .tres later.
## Returns the HSlider, so a caller that has to WRITE the value back (a pose editor changing which
## bone is selected, say) can do it without hunting the widget back out of the tree. Callers that
## only want to build a row ignore the return, exactly as before.
static func slider(box: VBoxContainer, name_: String, lo: float, hi: float, step: float,
		value: Variant, on_change: Callable) -> HSlider:
	var v := float(value) if value != null else lo
	var l := Label.new()
	l.text = "%s  %.2f" % [name_, v]
	l.add_theme_font_size_override("font_size", 12)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(276, 16)
	s.value_changed.connect(func(nv: float) -> void:
		l.text = "%s  %.2f" % [name_, nv]
		on_change.call(nv))
	box.add_child(s)
	return s


static func color(box: VBoxContainer, name_: String, value: Variant, on_change: Callable) -> void:
	var l := Label.new()
	l.text = name_
	l.add_theme_font_size_override("font_size", 12)
	box.add_child(l)
	var b := ColorPickerButton.new()
	b.color = (value as Color) if value != null else Color.WHITE
	b.custom_minimum_size = Vector2(276, 22)
	b.color_changed.connect(func(c: Color) -> void: on_change.call(c))
	box.add_child(b)


static func check(box: VBoxContainer, name_: String, pressed: bool, on_change: Callable) -> void:
	var c := CheckBox.new()
	c.text = name_
	c.button_pressed = pressed
	c.toggled.connect(func(on: bool) -> void: on_change.call(on))
	box.add_child(c)


static func button(box: VBoxContainer, name_: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = name_
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


## A plain read-only line. Returns it so a caller polling once a frame can rewrite `.text` rather
## than rebuilding the row.
## A NOTE UNDER A CONTROL, and it WRAPS - which is the whole of why these panels kept eating the
## thing they were built to look at.
##
## A Label's minimum width is its longest unwrapped line, and a VBox inside a PanelContainer takes
## its width from the widest child. So one explanatory sentence sets the width of the entire panel,
## and the number passed to build_panel is only ever a floor. The SWE lab hit this twice in an
## afternoon: a "no knob yet" list of six uniforms took the panel from 330 px to about 900, and an
## obstacle note did it again - both times covering half the 3D view, and both times the screenshot
## probe reported the water it could no longer see as "full and empty look the same".
##
## Wrapping makes the requested width the ACTUAL width, and the resize grip on the panel then means
## something: it is the only thing that changes the size, rather than whatever text was added last.
static func line(box: VBoxContainer, text: String, colour := Color(0.78, 0.78, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Without this the label still reports its unwrapped length as its minimum and wraps nothing.
	l.custom_minimum_size = Vector2(0, 0)
	l.size_flags_horizontal = Control.SIZE_FILL
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", colour)
	box.add_child(l)
	return l


## A scrolling pane for output that grows — a light census, a warnings list, a save diff. BBCode is
## on so a warning can be coloured without the caller building Labels.
static func log_pane(box: VBoxContainer, height := 150) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_following = false
	r.custom_minimum_size = Vector2(276, height)
	r.add_theme_font_size_override("normal_font_size", 11)
	box.add_child(r)
	return r


static func option(box: VBoxContainer, name_: String, items: PackedStringArray, selected: int,
		on_change: Callable) -> OptionButton:
	if name_ != "":
		line(box, name_)
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	if selected >= 0 and selected < items.size():
		o.select(selected)
	o.custom_minimum_size = Vector2(276, 22)
	o.item_selected.connect(func(i: int) -> void: on_change.call(i))
	box.add_child(o)
	return o


## Unbounded numeric entry, for the values a slider cannot serve: a light's position, a range that
## has no sensible upper bound, anything you want to type an exact number into rather than drag to.
static func number(box: VBoxContainer, name_: String, value: float, step: float,
		on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	box.add_child(row)
	var l := Label.new()
	l.text = name_
	l.add_theme_font_size_override("font_size", 11)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := SpinBox.new()
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.value = value
	s.custom_minimum_size = Vector2(120, 0)
	s.value_changed.connect(func(nv: float) -> void: on_change.call(nv))
	row.add_child(s)
	return s


# ------------------------------------------------------------------ generic rows --------------
#
# EVERY ROW ABOVE THIS LINE IS HAND-WRITTEN BY THE CALLER, and for a panel of forty that is the
# right trade — you get to name, group and bound each knob deliberately. scripts/dev/lookdev.gd and
# scripts/dev/whinbek_lookdev.gd each hand-write about forty-three.
#
# The crypt does not fit in that budget. dungeon_stone.gdshader alone declares forty-four uniforms,
# and the tuner also wants the Environment, the DungeonTheme and the full property set of whichever
# light is selected — comfortably past a hundred and twenty rows. Hand-writing those is not just
# tedious, it ROTS: a uniform added to the shader next month has no slider and nobody notices.
#
# So the two builders below read the metadata the engine already has. The bounds are not invented
# here — `hint_range(0.0, 8.0, 0.1)` in the shader source becomes exactly that slider, and an
# @export on a Resource becomes exactly its row. Add a uniform, get a knob.


## Build a row for every uniform a ShaderMaterial's shader declares. Returns the number of rows made.
##
## `on_change` is called as (name: String, value: Variant) AFTER the material is updated, so the
## caller can record old -> new for the save diff without duplicating the write.
##
## INSTANCE UNIFORMS ARE SKIPPED, and they have to be found by reading the shader source: they are
## per-MeshInstance3D (Kit sets `piece_params` and `piece_base` per piece via
## set_instance_shader_parameter), so a material-level slider for one would write a value the
## renderer never reads and leave you tuning a control that does nothing.
static func from_shader(box: VBoxContainer, mat: ShaderMaterial, on_change: Callable) -> int:
	if mat == null or mat.shader == null:
		line(box, "no ShaderMaterial", Color(1.0, 0.5, 0.4))
		return 0
	var per_instance := _instance_uniform_names(mat.shader.code)
	var made := 0
	for entry: Dictionary in mat.shader.get_shader_uniform_list(true):
		var usage := int(entry.get("usage", 0))
		var nm := String(entry.get("name", ""))
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			if nm != "":
				header(box, nm)
			continue
		if nm == "" or per_instance.has(nm):
			continue
		# get_shader_parameter returns null until something overrides it, so fall back to the value
		# the shader itself authored — otherwise every untouched slider would start at zero.
		var cur: Variant = mat.get_shader_parameter(nm)
		if cur == null:
			cur = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), nm)
		var setter := func(v: Variant) -> void:
			mat.set_shader_parameter(nm, v)
			on_change.call(nm, v)
		if _row(box, nm, int(entry.get("type", 0)), int(entry.get("hint", 0)),
				String(entry.get("hint_string", "")), cur, setter):
			made += 1
	return made


## The same idea against any Object's property list — Light3D, Environment, a DungeonTheme resource.
## `only` filters by name when non-empty; pass DungeonEnv.FIXED_ENV.keys() and you get exactly the
## properties the crypt override touches, in that order, with no second list to keep in step.
static func from_object(box: VBoxContainer, obj: Object, only: Array, on_change: Callable) -> int:
	if obj == null:
		return 0
	var made := 0
	var wanted := {}
	for k in only:
		wanted[String(k)] = true
	for entry: Dictionary in obj.get_property_list():
		var usage := int(entry.get("usage", 0))
		var nm := String(entry.get("name", ""))
		if usage & PROPERTY_USAGE_GROUP or usage & PROPERTY_USAGE_SUBGROUP:
			if wanted.is_empty() and nm != "":
				header(box, nm)
			continue
		if nm == "" or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if not wanted.is_empty() and not wanted.has(nm):
			continue
		var setter := func(v: Variant) -> void:
			obj.set(nm, v)
			on_change.call(nm, v)
		if _row(box, nm, int(entry.get("type", 0)), int(entry.get("hint", 0)),
				String(entry.get("hint_string", "")), obj.get(nm), setter):
			made += 1
	return made


## One row, chosen by type. Returns false for anything it deliberately will not edit (textures,
## resources, arrays) so the caller can count what it actually got.
static func _row(box: VBoxContainer, nm: String, type: int, hint: int, hint_string: String,
		cur: Variant, setter: Callable) -> bool:
	match type:
		TYPE_BOOL:
			check(box, nm, bool(cur), setter)
		TYPE_COLOR:
			color(box, nm, cur, setter)
		TYPE_FLOAT:
			var r := _range_of(hint, hint_string)
			if r.is_empty():
				number(box, nm, float(cur), 0.01, setter)
			else:
				slider(box, nm, r[0], r[1], r[2], cur, setter)
			return true
		TYPE_INT:
			var ri := _range_of(hint, hint_string)
			# Enums arrive as ints with the option names in hint_string — a dropdown, not a slider.
			if hint == PROPERTY_HINT_ENUM:
				var names := PackedStringArray()
				for opt in hint_string.split(","):
					names.append(opt.split(":")[0])
				option(box, nm, names, int(cur), func(i: int) -> void: setter.call(i))
			elif ri.is_empty():
				number(box, nm, float(cur), 1.0, func(v: float) -> void: setter.call(int(v)))
			else:
				slider(box, nm, ri[0], ri[1], maxf(ri[2], 1.0), cur,
						func(v: float) -> void: setter.call(int(v)))
			return true
		TYPE_VECTOR3:
			var v3 := cur as Vector3
			header(box, nm)
			number(box, "  x", v3.x, 0.01, func(v: float) -> void:
				v3.x = v
				setter.call(v3))
			number(box, "  y", v3.y, 0.01, func(v: float) -> void:
				v3.y = v
				setter.call(v3))
			number(box, "  z", v3.z, 0.01, func(v: float) -> void:
				v3.z = v
				setter.call(v3))
			return true
		_:
			return false
	return true


## "0,1,0.01" or "0,1,0.01,or_greater" -> [lo, hi, step]. Empty when the property has no range, in
## which case the caller falls back to unbounded numeric entry rather than inventing bounds.
static func _range_of(hint: int, hint_string: String) -> Array:
	if hint != PROPERTY_HINT_RANGE:
		return []
	var parts := hint_string.split(",")
	if parts.size() < 2:
		return []
	var lo := float(parts[0])
	var hi := float(parts[1])
	var step := float(parts[2]) if parts.size() > 2 and parts[2].is_valid_float() else 0.01
	return [lo, hi, step]


## Names declared `instance uniform` in the shader source. There is no flag for this on the entries
## get_shader_uniform_list returns, so the source is the only place to ask.
static func _instance_uniform_names(code: String) -> Dictionary:
	var out := {}
	for raw in code.split("\n"):
		var l := raw.strip_edges()
		if not l.begins_with("instance uniform "):
			continue
		# `instance uniform vec4 piece_params;`  ->  piece_params
		var body := l.substr("instance uniform ".length())
		var tokens := body.split(" ", false)
		if tokens.size() >= 2:
			out[tokens[1].split(";")[0].split(":")[0].strip_edges()] = true
	return out
