extends Node
## Autoload "Notice" — the check card: the moment one of your characteristics gets a word in.
##
## Time drops to a quarter, a card slides in at the top of the screen headed
## `LOGIC [Medium: Success]`, the line types itself out, and you dismiss it. That interruption IS
## the psychological texture of this game — not a personified cast, just the fact that what you
## notice depends on what you are.
##
## Built in code on one CanvasLayer, the same doctrine as Dialogue and Hud: no scene has to provide
## anything to make a check fire.
##
## LAYERS: kuwahara 9 · grade 10 · HUD 20 · dialogue 25 · NOTICE 26 · sheet 27 · map 28 · pause 30

signal card_closed                             ## one card finished (used to wake awaiting callers)

const WIDTH := 660.0
const TYPE_CPS := 45.0                         ## matches Dialogue, so the whole game types alike
const SLOW := 0.25                             ## time scale while a card is up
const HOLD := 2.4                              ## seconds before it leaves on its own
const QUEUE_MAX := 2                           ## a third simultaneous voice is DROPPED, not stacked

var active := false

var _queue: Array[Dictionary] = []
var _running := false
var _typing := false
var _tween: Tween

## HOW MANY THINGS CURRENTLY WANT TIME SLOWED. Cards can overlap at the edges (one closing as the
## next opens), and releasing on the first close would snap the game back to full speed underneath
## the second card.
var _holds := 0

# --- UI ---
var _root: Control
var _card: PanelContainer
var _bar: ColorRect
var _header: Label
var _tagline: Label
var _text: RichTextLabel


func _ready() -> void:
	# ALWAYS, because a card can be up while something else has frozen the tree, and a card that
	# stops processing never dismisses itself — it just sits there forever.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


## THE TIME SCALE IS RE-ASSERTED EVERY FRAME, not set once.
##
## Fx.hitstop is the other writer of Engine.time_scale, and it does not refcount: it drops the scale,
## waits in real time, then assigns 1.0 flat. A hit landing during a card would therefore hand the
## game back to full speed mid-sentence — and a card opening during a hitstop would be undone by
## that hitstop's own restore a few dozen milliseconds later. Neither is fixable from this end by
## being careful about ordering, because the clobber happens inside another autoload's await.
##
## So while anything holds the slow, this simply keeps saying so. The cost is that a hit landing
## during a card gets no hitstop, which is the right trade: the card IS the pause.
func _process(_delta: float) -> void:
	if _holds > 0 and not is_equal_approx(Engine.time_scale, SLOW):
		Engine.time_scale = SLOW


## Roll a check and show the result. Awaitable — returns the check Dictionary once the card is gone.
##
## A check whose id ALREADY resolved this run returns its cached result immediately and shows
## nothing: re-entering a room must not replay the sentence, and must certainly not slow time again.
func interject(which: int, difficulty: String, id: String, on_success: String, on_fail: String,
		hold := HOLD) -> Dictionary:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return {}
	if id != "":
		var seen: Dictionary = traits.check_result(id)
		if not seen.is_empty():
			return seen
	var result: Dictionary = traits.check(which, difficulty, id)
	var verdict := "Success" if result.success else "Failure"
	if result.critical:
		verdict = "Success"
	elif result.fumble:
		verdict = "Failure"
	await _present({
		"attr": which,
		"header": "%s  [%s: %s]" % [traits.ATTR_NAMES[which],
				String(difficulty).capitalize(), verdict],
		"text": on_success if result.success else on_fail,
		"dim": not result.success,
		"hold": hold,
	})
	return result


## A line with no dice behind it — the world telling you something your characteristics simply let
## you see. Same card, no verdict in the header.
func murmur(which: int, text: String, hold := 2.2) -> void:
	var traits := get_node_or_null("/root/Traits")
	if traits == null:
		return
	await _present({
		"attr": which,
		"header": traits.ATTR_NAMES[which],
		"text": text,
		"dim": false,
		"hold": hold,
	})


func _present(entry: Dictionary) -> void:
	if _queue.size() >= QUEUE_MAX:
		return                                 # two voices are a conversation, three are noise
	entry["live"] = true
	_queue.append(entry)
	if not _running:
		_pump()
	# Dictionaries are by reference, so the pump clearing `live` on THIS entry is what wakes us —
	# which is how two callers awaiting at once each return at their own card's end.
	while entry.live:
		await card_closed


func _pump() -> void:
	_running = true
	_holds += 1
	Engine.time_scale = SLOW
	while not _queue.is_empty():
		var entry: Dictionary = _queue[0]
		await _run_card(entry)
		_queue.pop_front()
		entry["live"] = false
		# SETTLE BEFORE WAKING ANYBODY. card_closed used to fire while `active` was still true, and
		# a waiter that re-tests `active` when it wakes — which is the obvious way to write
		# "wait until the voice has finished" — re-armed on a signal that would never come again
		# and hung forever. Sheet._open did exactly that, so a boon pick opened while a card was
		# fading never appeared at all, and the pedestal was consumed regardless.
		if _queue.is_empty():
			_settle()
		card_closed.emit()
	_settle()                              # the queue was empty to begin with


func _settle() -> void:
	if not _running:
		return
	_running = false
	active = false
	_root.visible = false
	_holds = maxi(_holds - 1, 0)
	if _holds == 0:
		Engine.time_scale = 1.0


func _run_card(entry: Dictionary) -> void:
	var traits := get_node_or_null("/root/Traits")
	var tint: Color = traits.ATTR_COLORS[int(entry.attr)] if traits else Color.WHITE
	if entry.dim:
		# A FAILED check is the same card, drained — not a different one and never a silent one.
		# Being wrong out loud is most of the character in this system.
		tint = tint.lerp(Color(0.55, 0.55, 0.58), 0.55)
	_bar.color = tint
	_header.text = String(entry.header)
	_header.add_theme_color_override("font_color", tint)
	_tagline.text = traits.ATTR_TAGLINE[int(entry.attr)] if traits else ""
	_tagline.add_theme_color_override("font_color", Color(tint.r, tint.g, tint.b, 0.5))
	_card.add_theme_stylebox_override("panel", _panel_style(tint))

	active = true
	_root.visible = true
	_root.modulate.a = 0.0
	var fade := create_tween()
	fade.set_ignore_time_scale(true)
	fade.tween_property(_root, "modulate:a", 1.0, 0.14)

	_type(String(entry.text))
	# Real time throughout: the card lives at wall-clock speed while the WORLD is the thing that
	# slowed down. Tying it to the scaled clock would make a 2.4 s card last nearly ten seconds.
	var elapsed := 0.0
	var limit: float = float(entry.hold) + String(entry.text).length() / TYPE_CPS
	while elapsed < limit and active:
		await get_tree().create_timer(0.05, true, false, true).timeout
		elapsed += 0.05
	var out := create_tween()
	out.set_ignore_time_scale(true)
	out.tween_property(_root, "modulate:a", 0.0, 0.16)
	await out.finished


func _type(line: String) -> void:
	_text.text = line
	_text.visible_ratio = 0.0
	_typing = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_text, "visible_ratio", 1.0, maxf(0.15, line.length() / TYPE_CPS))
	_tween.tween_callback(func() -> void: _typing = false)


## First press finishes the typewriter, second dismisses the card. Runs in _input (ahead of
## gameplay's _unhandled_input) so the same press cannot also swing the sword.
func _input(event: InputEvent) -> void:
	if not active:
		return
	var accept := event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if not (accept or click):
		return
	if _typing:
		if _tween:
			_tween.kill()
		_text.visible_ratio = 1.0
		_typing = false
	else:
		active = false                         # ends the wait loop in _run_card
	get_viewport().set_input_as_handled()


# ----------------------------------------------------------------------------------------------
# UI. Top-centre: clear of the bottom-left HUD and clear of Dialogue's bottom bar, so a check can
# fire during a conversation without the two overlapping.
# ----------------------------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 26
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	layer.add_child(_root)

	_card = PanelContainer.new()
	# anchor_bottom stays 0 and offset_bottom is left alone: a Control's size is clamped UP to its
	# combined minimum, so the card is exactly 660 wide and exactly as tall as its text.
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -WIDTH * 0.5
	_card.offset_right = WIDTH * 0.5
	_card.offset_top = 54
	_root.add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_card.add_child(row)

	# The colour bar is the fastest read on the card — you know who is talking before you read a
	# word of it.
	_bar = ColorRect.new()
	_bar.custom_minimum_size = Vector2(5, 0)
	_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	margin.add_child(vb)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 19)
	vb.add_child(_header)

	_tagline = Label.new()
	_tagline.add_theme_font_size_override("font_size", 12)
	vb.add_child(_tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	vb.add_child(gap)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_color_override("default_color", Color(0.93, 0.91, 0.88))
	vb.add_child(_text)


func _panel_style(tint: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.07, 0.93)
	s.set_corner_radius_all(4)
	s.border_color = Color(tint.r, tint.g, tint.b, 0.45)
	s.border_width_bottom = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.set_content_margin_all(0)
	return s
