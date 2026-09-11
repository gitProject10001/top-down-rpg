extends Node
## Autoload "Sheet" — the three screens where a choice actually gets made:
##
##   offer_boons()      1 of 3, on every room clear                    (the descent's shape)
##   open_convictions() what the last descents left in you             (the slow, permanent one)
##   open_characteristics()  where the points go                       (the sheet itself)
##
## One backdrop, one build/teardown, three fillers — because three near-identical panel builders is
## how a menu system starts lying about state.
##
## FREEZING GOES THROUGH Pause.hold(), never get_tree().paused. pause_menu.gd owns that flag and
## DERIVES the menu's own state from it; a second writer desynchronises the pair, and the symptom is
## the world unfreezing with a screen still up.
##
## LAYERS: kuwahara 9 · grade 10 · HUD 20 · dialogue 25 · notice 26 · SHEET 27 · map 28 · pause 30

const ACCENT := Color(1.0, 0.82, 0.5)
const CARD_W := 300.0

var active := false

var _mode := ""                                ## "boons" | "convictions" | "characteristics"
var _offer: Array[String] = []                 ## the three ids currently on the table

var _root: Control
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # it freezes the tree, then has to keep drawing
	_build_ui()


# --- the three entry points -------------------------------------------------------------------

## THE HADES BEAT: a boon is not optional. There is no Escape out of this one — you cleared the
## room, you are taking something, and the only question is what.
func offer_boons() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null or active:
		return
	_offer = traits.offer_boons(3)
	if _offer.is_empty():
		return
	_open("boons", "SOMETHING SETTLES", "The room is quiet. Take one.")


func open_convictions() -> void:
	if active:
		return
	_open("convictions", "WHAT IT LEFT IN YOU",
			"Sitting with an idea costs a slot and several descents. It changes you either way.")


func open_characteristics() -> void:
	if active:
		return
	_open("characteristics", "THE SHEET",
			"Four numbers. Each one is a way of fighting, a way of looking, and a way of talking.")


## The end card. Not escapable by Escape either — you finished it, you get to look at it.
func show_finale() -> void:
	if active:
		return
	_open("finale", "THE DESCENT IS COMPLETE", "")


func close() -> void:
	if not active:
		return
	active = false
	_mode = ""
	_root.visible = false
	var pause := get_node_or_null("/root/Pause")
	if pause:
		pause.hold(&"sheet", false)
	var hud := get_node_or_null("/root/Hud")
	if hud:
		hud.suppress(false)


func _open(mode: String, title: String, subtitle: String) -> void:
	# LET THE VOICE FINISH. A pedestal is walked into, and a check card fires from an Area3D the
	# player may have crossed a moment earlier — so the two genuinely race. The panel would win
	# (layer 27 over 26) and the card would sit greyed out underneath it, still counting down,
	# still holding time_scale at a quarter. Waiting costs a beat and reads as deliberate.
	# POLLED AND BOUNDED, not an await on card_closed. Waiting on a signal here is what deadlocked:
	# it fired while Notice was still reporting itself active, so this re-armed and never woke. A
	# bounded poll cannot hang whatever Notice does, and after three seconds it simply proceeds —
	# a card overlapping the panel is untidy, a panel that never opens is a lost boon.
	var notice := get_node_or_null("/root/Notice")
	var guard := 0
	while notice and notice.active and guard < 60:
		await get_tree().create_timer(0.05, true, false, true).timeout
		guard += 1
	_mode = mode
	active = true
	_title.text = title
	_subtitle.text = subtitle
	_hint.visible = mode != "boons"
	_root.visible = true
	var pause := get_node_or_null("/root/Pause")
	if pause:
		pause.hold(&"sheet", true)
	var hud := get_node_or_null("/root/Hud")
	if hud:
		hud.suppress(true)
	_rebuild()


## Everything that changes state calls this rather than patching a label, so the screen can never
## disagree with the model about how many slots are left or what a point now costs.
func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return
	var first: Control = null
	match _mode:
		"boons":
			first = _fill_boons(traits)
		"convictions":
			first = _fill_convictions(traits)
		"characteristics":
			first = _fill_characteristics(traits)
		"finale":
			first = _fill_finale(traits)
	if first:
		first.call_deferred("grab_focus")        # deferred: the old children free this frame


# --- boons --------------------------------------------------------------------------------------

func _fill_boons(traits: Node) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)

	var first: Control = null
	for id in _offer:
		var boon: Dictionary = traits.BOONS[id]
		var tint: Color = traits.ATTR_COLORS[int(boon.attr)]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_style(tint))
		card.custom_minimum_size = Vector2(CARD_W, 0)
		row.add_child(card)

		var pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 16)
		card.add_child(pad)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		pad.add_child(vb)

		vb.add_child(_label(traits.ATTR_NAMES[int(boon.attr)], 13, tint))
		vb.add_child(_label(String(boon.name), 21, Color(0.95, 0.93, 0.9)))
		var body := _label(String(boon.text), 15, Color(0.78, 0.76, 0.74))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(CARD_W - 32, 0)
		vb.add_child(body)

		var take := Button.new()
		take.text = "Take"
		take.custom_minimum_size = Vector2(0, 38)
		take.add_theme_font_size_override("font_size", 17)
		take.pressed.connect(_take_boon.bind(id))
		vb.add_child(take)
		if first == null:
			first = take
	return first


func _take_boon(id: String) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.take_boon(id)
	close()


# --- convictions ---------------------------------------------------------------------------------

func _fill_convictions(traits: Node) -> Control:
	_subtitle.text = "%d of %d slots in use.   Insight: %d" % [
			traits.slots_used(), traits.slots, traits.insight]
	var first: Control = null
	var any := false
	for id: String in traits.CONVICTIONS:
		var state: String = traits.conviction_state(id)
		if state == "":
			continue                             # not yet acquired: it is not yours to think about
		any = true
		var data: Dictionary = traits.CONVICTIONS[id]
		var held: Dictionary = traits.convictions[id]
		var card := PanelContainer.new()
		var tint := ACCENT if state == "settled" else Color(0.55, 0.55, 0.62)
		card.add_theme_stylebox_override("panel", _card_style(tint))
		_body.add_child(card)

		var pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 14)
		card.add_child(pad)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		pad.add_child(vb)
		vb.add_child(_label(String(data.name), 19, tint))

		var line := ""
		match state:
			"loose":
				line = String(data.hook)
			"held":
				line = "%s\n\nThought about: %d of %d descents." % [
						String(data.body), int(held.progress), int(data.runs)]
			"settled":
				line = String(data.done)
		var body := _label(line, 15, Color(0.8, 0.78, 0.76) if state != "settled"
				else Color(0.62, 0.6, 0.58))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(680, 0)
		vb.add_child(body)

		if state == "loose":
			var btn := Button.new()
			var room: bool = traits.slots_used() < traits.slots
			btn.text = "Sit with it" if room else "No slot free"
			btn.disabled = not room
			btn.custom_minimum_size = Vector2(180, 34)
			btn.pressed.connect(_take_up.bind(id))
			vb.add_child(btn)
			if first == null:
				first = btn

	if not any:
		var none := _label("Nothing yet. Ideas are not bought — something has to happen to you.",
				16, Color(0.7, 0.68, 0.66))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(680, 0)
		_body.add_child(none)

	# ROOM TO THINK, bought with the Insight a finished sheet has nothing else to do with. Slots are
	# the slower half of the progression — two at a time against four ideas that take two or three
	# descents each — so this is the thing a maxed player is actually still short of.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_body.add_child(gap)
	var slot_btn := Button.new()
	var price: int = traits.slot_price()
	if traits.can_buy_slot():
		slot_btn.text = "Make room for a %s idea  —  %d Insight" % [
				["third", "fourth"][clampi(traits.slots - 2, 0, 1)], price]
		slot_btn.disabled = traits.insight < price
	else:
		slot_btn.text = "You have room for every idea there is."
		slot_btn.disabled = true
	slot_btn.custom_minimum_size = Vector2(360, 40)
	slot_btn.add_theme_font_size_override("font_size", 16)
	slot_btn.pressed.connect(_buy_slot)
	_body.add_child(slot_btn)
	if first == null and not slot_btn.disabled:
		first = slot_btn
	return first


func _take_up(id: String) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.take_up(id)
	_rebuild()


func _buy_slot() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.buy_slot()
	_rebuild()


# --- the ending ---------------------------------------------------------------------------------

## A record rather than a screen: every row is something this descent actually did.
func _fill_finale(traits: Node) -> Control:
	for row: Array in Finale.card(traits):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		_body.add_child(line)
		var label := _label(String(row[0]), 16, Color(0.68, 0.66, 0.64))
		label.custom_minimum_size = Vector2(300, 0)
		line.add_child(label)
		line.add_child(_label(String(row[1]), 16, ACCENT))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	_body.add_child(gap)

	# NOT named `close`: a local of that name shadows this class's own close() method, and
	# `close.pressed.connect(close)` then wires the button to itself instead of to the method.
	var back := Button.new()
	back.text = "Back to the top of the stairs"
	back.custom_minimum_size = Vector2(340, 42)
	back.add_theme_font_size_override("font_size", 17)
	back.pressed.connect(close)
	_body.add_child(back)
	return back


# --- characteristics ------------------------------------------------------------------------------

func _fill_characteristics(traits: Node) -> Control:
	_subtitle.text = "Insight: %d      Unspent points: %d" % [traits.insight, traits.unspent]
	var first: Control = null
	for i in 4:
		var tint: Color = traits.ATTR_COLORS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_body.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = tint
		swatch.custom_minimum_size = Vector2(6, 40)
		row.add_child(swatch)

		var names := VBoxContainer.new()
		names.custom_minimum_size = Vector2(210, 0)
		names.add_theme_constant_override("separation", 0)
		row.add_child(names)
		names.add_child(_label(traits.ATTR_NAMES[i], 19, tint))
		names.add_child(_label(traits.ATTR_TAGLINE[i], 12, Color(tint.r, tint.g, tint.b, 0.5)))

		# Pips rather than a number: five filled blocks say "most of the way" at a glance, and the
		# sheet is read far more often than it is changed.
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 4)
		pips.custom_minimum_size = Vector2(140, 0)
		row.add_child(pips)
		for p in traits.MAX_ATTR:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(18, 18)
			pip.color = tint if p < traits.attr(i) else Color(0.18, 0.18, 0.21)
			pips.add_child(pip)

		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(44, 34)
		plus.disabled = traits.unspent <= 0 or traits.attr(i) >= traits.MAX_ATTR
		plus.pressed.connect(_spend.bind(i))
		row.add_child(plus)
		if first == null and not plus.disabled:
			first = plus

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	_body.add_child(gap)

	var price: int = traits.point_price()
	var buy := Button.new()
	# SAY SO WHEN THERE IS NOTHING LEFT TO BUY. Quoting a price for a point that cannot be placed
	# is how a player spends an entire run's Insight on nothing and has to work out why from the
	# absence of a change.
	var room_left: bool = traits.can_place_point()
	buy.text = "Buy a point  —  %d Insight" % price if room_left \
			else "Nothing left to raise. The sheet is finished."
	buy.custom_minimum_size = Vector2(300, 40)
	buy.add_theme_font_size_override("font_size", 17)
	buy.disabled = not room_left or traits.insight < price
	buy.pressed.connect(_buy)
	_body.add_child(buy)
	if first == null and not buy.disabled:
		first = buy
	return first


func _spend(which: int) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.spend_point(which)
	_rebuild()


func _buy() -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits:
		traits.buy_point()
	_rebuild()


# ----------------------------------------------------------------------------------------------

## Escape closes everything except the boon pick. Consumed here so it cannot also reach Pause and
## stack the pause menu underneath this one.
func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		# The boon pick cannot be escaped (the Hades beat), and neither can the ending — you
		# finished it, you get to look at it.
		if _mode != "boons" and _mode != "finale":
			close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 27
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # eat clicks so none reach the game
	_root.visible = false
	layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(column)

	_title = _label("", 34, ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_subtitle = _label("", 15, Color(0.72, 0.7, 0.68))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	column.add_child(gap)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	column.add_child(_body)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 16)
	column.add_child(gap2)

	_hint = _label("Esc to step away", 13, Color(0.55, 0.53, 0.51))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _card_style(tint: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = Color(tint.r, tint.g, tint.b, 0.55)
	s.set_content_margin_all(0)
	return s
