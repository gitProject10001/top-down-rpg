extends Node
## Autoload "Dialogue" — a Hades-style conversation runner.
##
## Placeholder portrait + speaker name + typewriter text + branching PLAYER RESPONSES.
## An NPC starts one with `Dialogue.start(convo)`; gameplay input is frozen while it runs
## (the player checks `Dialogue.active`).
##
## CONVERSATION FORMAT — a Dictionary of node_id -> node:
##   {
##     "start": {
##        "speaker": "Dusa",                       # name shown + placeholder portrait initial
##        "text": "Oh! Hello again.",              # the line (typewriters in)
##        "responses": [                           # player choices (optional)
##           {"text": "Hi, Dusa.", "next": "a"},   # "next" = node to jump to ("" / missing = end)
##           {"text": "Goodbye.",  "next": ""},
##        ],
##     },
##     # A node with NO "responses" just shows a ▼ continue prompt and advances to "next":
##     "a": {"speaker": "Dusa", "text": "...", "next": "b"},
##   }
##
## The UI is built in code (one CanvasLayer) so any scene can trigger dialogue with zero setup.

signal started
signal finished
## A conversation node was entered, by its id. The hook for a line that DOES something — a check
## rolled, a gate opened, a tool handed over. Without it a conversation can only ever route to more
## conversation, and every consequence has to be inferred from where it happened to stop.
signal node_entered(id: String)

var active := false

const TYPE_CPS := 45.0                       ## typewriter speed (characters / second)
const ACCENT := Color(1.0, 0.82, 0.5)        ## warm gold — matches the painterly palette

var _convo: Dictionary = {}
var _node := ""
var _typing := false
var _tween: Tween

# --- UI (built in _ready) ---
var _root: Control
var _name_lbl: Label
var _text_lbl: RichTextLabel
var _portrait_lbl: Label
var _responses: VBoxContainer
var _continue: Label


func _ready() -> void:
	_build_ui()


## Begin a conversation at `first` (default "start"). No-op if one is already running.
func start(convo: Dictionary, first := "start") -> void:
	if active or convo.is_empty():
		return
	_convo = convo
	active = true
	_root.visible = true
	started.emit()
	_show(first)


func _show(id: String) -> void:
	if id == "" or not _convo.has(id):
		_end()
		return
	_node = id
	node_entered.emit(id)
	var n: Dictionary = _convo[id]
	var speaker: String = n.get("speaker", "")
	_name_lbl.text = speaker
	_portrait_lbl.text = speaker.substr(0, 1).to_upper() if speaker != "" else "?"
	for c in _responses.get_children():
		c.queue_free()
	_responses.visible = false
	_continue.visible = false
	_type(n.get("text", ""))


func _type(line: String) -> void:
	_text_lbl.text = line
	_text_lbl.visible_ratio = 0.0
	_typing = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text_lbl, "visible_ratio", 1.0, maxf(0.15, line.length() / TYPE_CPS))
	_tween.tween_callback(_on_typed)


func _on_typed() -> void:
	_typing = false
	var resp: Array = _convo[_node].get("responses", [])
	if resp.is_empty():
		_continue.visible = true
	else:
		_build_responses(resp)


func _build_responses(resp: Array) -> void:
	var first_btn: Button = null
	for r in resp:
		var b := Button.new()
		b.text = r.get("text", "...")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", 18)
		var nxt: String = r.get("next", "")
		b.pressed.connect(_choose.bind(nxt))
		_responses.add_child(b)
		if first_btn == null:
			first_btn = b
	_responses.visible = true
	if first_btn:
		first_btn.grab_focus()


func _choose(next: String) -> void:
	_show(next)


func _skip() -> void:
	if _tween:
		_tween.kill()
	_text_lbl.visible_ratio = 1.0
	_on_typed()


func _advance() -> void:
	_show(_convo[_node].get("next", ""))


func _end() -> void:
	active = false
	_root.visible = false
	_node = ""
	_convo = {}
	finished.emit()


## Dialogue owns input while active. Runs in _input (before gameplay's _unhandled_input), so
## the same key press can't also drive the player. Choices are picked by the focused Button
## (arrow keys move focus, Enter/click/E confirm).
func _input(event: InputEvent) -> void:
	if not active:
		return
	var accept := event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
	var click := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if _typing:
		if accept or click:
			_skip()
			get_viewport().set_input_as_handled()
		return
	var has_resp: bool = not (_convo[_node].get("responses", []) as Array).is_empty()
	if has_resp:
		# Enter/click confirm the focused button natively; map E (interact) to it too.
		if event.is_action_pressed("interact"):
			var f := get_viewport().gui_get_focus_owner()
			if f is Button:
				(f as Button).pressed.emit()
			get_viewport().set_input_as_handled()
	elif accept or click:
		_advance()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------------------------
# UI construction (Hades-style: raised portrait on the left, a dark text bar along the bottom,
# player choices stacked on the right). Portraits are PLACEHOLDERS for now — a tinted panel with
# the speaker's initial; drop a TextureRect in later.
# --------------------------------------------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25                       # above the painterly grade (layer 10)
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # eat clicks so they never reach the game
	_root.visible = false
	layer.add_child(_root)

	# text bar along the bottom, left edge cleared for the portrait
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.05, 0.08, 0.92)))
	_anchor(box, 0, 1, 1, 1, 300, -180, -48, -40)
	_root.add_child(box)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	box.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 22)
	_name_lbl.add_theme_color_override("font_color", ACCENT)
	vb.add_child(_name_lbl)

	_text_lbl = RichTextLabel.new()
	_text_lbl.bbcode_enabled = true
	_text_lbl.fit_content = true
	_text_lbl.scroll_active = false
	_text_lbl.add_theme_font_size_override("normal_font_size", 20)
	_text_lbl.add_theme_color_override("default_color", Color(0.93, 0.9, 0.85))
	_text_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_text_lbl)

	# raised portrait placeholder, bottom-left
	var ppanel := PanelContainer.new()
	ppanel.add_theme_stylebox_override("panel", _panel_style(Color(0.11, 0.1, 0.14, 0.96)))
	_anchor(ppanel, 0, 1, 0, 1, 44, -330, 268, -70)
	_root.add_child(ppanel)

	_portrait_lbl = Label.new()
	_portrait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_lbl.add_theme_font_size_override("font_size", 96)
	_portrait_lbl.add_theme_color_override("font_color", Color(0.4, 0.38, 0.45))
	ppanel.add_child(_portrait_lbl)

	# player responses, stacked above the text bar on the right
	_responses = VBoxContainer.new()
	_responses.alignment = BoxContainer.ALIGNMENT_END
	_responses.add_theme_constant_override("separation", 6)
	_anchor(_responses, 1, 1, 1, 1, -520, -430, -48, -196)
	_responses.visible = false
	_root.add_child(_responses)

	# ▼ continue prompt (only when a line has no choices)
	_continue = Label.new()
	_continue.text = "▼  E"
	_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue.add_theme_font_size_override("font_size", 16)
	_continue.add_theme_color_override("font_color", ACCENT)
	_anchor(_continue, 1, 1, 1, 1, -120, -86, -60, -56)
	_continue.visible = false
	_root.add_child(_continue)


## Anchor helper: set anchors (l,t,r,b in 0..1) + pixel offsets in one call.
func _anchor(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = orr; c.offset_bottom = ob


func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(1.0, 0.82, 0.5, 0.35)
	s.set_content_margin_all(4)
	return s
