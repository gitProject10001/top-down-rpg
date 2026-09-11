extends CanvasLayer
## A LIVE SLIDER PANEL for every dial that decides how test_pixelart looks.
##
## WHY THIS EXISTS. Tuning a look by editing a .tres, re-importing and re-rendering is a terrible
## feedback loop -- it is minutes per guess, and a look is found by making twenty guesses in a row
## while staring at the result. Every number below used to be a file edit. Now it is a slider, the
## scene updates as it moves, and PRINT VALUES writes the whole set to the console in .tres syntax
## so a good state can be pasted straight back into assets/materials/pixelart/post.tres.
##
## The panel lives on CanvasLayer 40 -- the dev-panel slot in the CanvasLayer contract that
## docs/architecture.md sets out -- and OUTSIDE the SubViewport, so its text stays sharp instead of
## being pixelated along with the world.
##
## Nothing here is written to disk. Close the game and the tuning is gone; that is deliberate, so an
## experiment can never quietly become the committed look.

const ROW_WIDTH := 300.0

## Filled in by the owner before the panel enters the tree.
var post_material: ShaderMaterial = null
var sun: DirectionalLight3D = null
var fire: OmniLight3D = null
var ground_material: ShaderMaterial = null
var container: SubViewportContainer = null
var post_quad: MeshInstance3D = null

var _rows: Array = []
var _box: VBoxContainer = null
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 40
	_panel = PanelContainer.new()
	_panel.position = Vector2(10, 10)
	_panel.self_modulate = Color(0, 0, 0, 0.72)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_panel.add_child(margin)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 2)
	margin.add_child(_box)

	_heading("TEST_PIXELART  —  look controls")
	_toggles()

	_heading("Tone")
	_shader_row("Exposure", &"exposure", 0.2, 6.0, 0.01)
	_shader_row("White point", &"white_point", 0.5, 8.0, 0.05)
	_shader_row("Contrast", &"contrast", 0.5, 2.0, 0.01)
	_shader_row("Saturation", &"saturation", 0.0, 2.0, 0.01)
	_shader_row("Split toning", &"split_strength", 0.0, 1.0, 0.01)
	_shader_row("Vignette", &"vignette", 0.0, 1.0, 0.01)

	_heading("Outline")
	_shader_row("Strength", &"outline_strength", 0.0, 1.0, 0.01)
	_shader_row("Depth threshold", &"depth_edge", 0.0005, 0.12, 0.0005)
	_shader_row("Normal threshold", &"normal_edge", 0.0, 1.0, 0.005)
	_shader_row("Ink from surface", &"ink_from_surface", 0.0, 1.0, 0.01)
	_shader_row("Far-ink floor", &"ink_fade_floor", 0.0, 1.0, 0.01)
	_shader_row("Fade starts (m)", &"ink_fade_start", 0.0, 120.0, 1.0)
	_shader_row("Fade ends (m)", &"ink_fade_end", 0.0, 200.0, 1.0)

	_heading("Palette")
	_shader_row("Palette mix", &"palette_mix", 0.0, 1.0, 0.01)
	_shader_row("Dither", &"dither", 0.0, 0.3, 0.002)

	_heading("Light")
	if sun != null:
		_prop_row("Sun energy", sun, &"light_energy", 0.0, 12.0, 0.05)
		_prop_row("Sun softness", sun, &"light_angular_distance", 0.0, 6.0, 0.05)
	if fire != null:
		_prop_row("Hearth energy", fire, &"light_energy", 0.0, 30.0, 0.1)

	if ground_material != null:
		_heading("Ground")
		_ground_row("Texture metres", &"texture_metres", 0.5, 20.0, 0.1)
		_ground_row("Desaturate", &"texture_desaturate", 0.0, 1.0, 0.01)
		_ground_row("Relief (m)", &"relief", 0.0, 3.0, 0.01)
		_ground_row("Weeds", &"weed_amount", 0.0, 1.0, 0.01)
		_ground_row("Weed patch (m)", &"weed_metres", 1.0, 30.0, 0.1)
		_ground_row("Water level", &"water_level", 0.0, 1.0, 0.01)

	var print_button := Button.new()
	print_button.text = "PRINT VALUES  (to console, .tres syntax)"
	print_button.pressed.connect(_print_values)
	_box.add_child(print_button)

	var hint := Label.new()
	hint.text = "TAB hides this panel"
	hint.add_theme_font_size_override(&"font_size", 11)
	hint.self_modulate = Color(1, 1, 1, 0.55)
	_box.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_TAB:
			_panel.visible = not _panel.visible
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------------------ row builders ----


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 12)
	label.self_modulate = Color(1, 0.88, 0.62)
	_box.add_child(label)


func _toggles() -> void:
	var row := HBoxContainer.new()
	_box.add_child(row)

	if post_quad != null:
		var post_check := CheckBox.new()
		post_check.text = "post"
		post_check.button_pressed = post_quad.visible
		post_check.toggled.connect(func(on: bool) -> void: post_quad.visible = on)
		row.add_child(post_check)

	if container != null:
		var label := Label.new()
		label.text = "  pixelation 1/"
		row.add_child(label)
		var option := OptionButton.new()
		for n in [1, 2, 3, 4]:
			option.add_item(str(n), n)
		option.select(max(0, [1, 2, 3, 4].find(container.stretch_shrink)))
		option.item_selected.connect(func(i: int) -> void:
			container.stretch_shrink = option.get_item_id(i))
		row.add_child(option)


## A slider bound to a uniform on the post-process material.
func _shader_row(label: String, param: StringName, lo: float, hi: float, step: float) -> void:
	if post_material == null:
		return
	_bind(label, lo, hi, step,
		func() -> float: return float(post_material.get_shader_parameter(param)),
		func(v: float) -> void: post_material.set_shader_parameter(param, v),
		"post", param)


func _ground_row(label: String, param: StringName, lo: float, hi: float, step: float) -> void:
	_bind(label, lo, hi, step,
		func() -> float: return float(ground_material.get_shader_parameter(param)),
		func(v: float) -> void: ground_material.set_shader_parameter(param, v),
		"ground", param)


## A slider bound to a plain property on a node -- light energies and the like.
func _prop_row(label: String, node: Node, prop: StringName, lo: float, hi: float, step: float) -> void:
	_bind(label, lo, hi, step,
		func() -> float: return float(node.get(prop)),
		func(v: float) -> void: node.set(prop, v),
		node.name, prop)


func _bind(label: String, lo: float, hi: float, step: float,
		getter: Callable, setter: Callable, group: String, key: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	_box.add_child(row)

	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 118
	name_label.add_theme_font_size_override(&"font_size", 12)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.x = ROW_WIDTH
	slider.value = getter.call()
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 52
	value_label.add_theme_font_size_override(&"font_size", 12)
	value_label.text = _fmt(slider.value, step)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		value_label.text = _fmt(v, step))

	_rows.append({"group": group, "key": key, "getter": getter, "step": step})


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(v))
	if step >= 0.01:
		return "%.2f" % v
	return "%.4f" % v


## Dump everything in a form that can be pasted back into the .tres files, so a tuning session ends
## with something durable rather than with a screenshot and a memory.
func _print_values() -> void:
	var by_group := {}
	for row in _rows:
		var g: String = row["group"]
		if not by_group.has(g):
			by_group[g] = []
		by_group[g].append(row)
	print("\n; ---- test_pixelart look, %s ----" % Time.get_datetime_string_from_system())
	for g in by_group:
		print("; [%s]" % g)
		for row in by_group[g]:
			var v: float = row["getter"].call()
			if g == "post" or g == "ground":
				print("shader_parameter/%s = %s" % [row["key"], _fmt(v, row["step"])])
			else:
				print("%s = %s" % [row["key"], _fmt(v, row["step"])])
	print("")
