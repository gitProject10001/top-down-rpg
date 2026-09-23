extends Control
## Pannello di conversazione riutilizzabile, costruito in codice (come le altre UI del progetto). Mostra
## SOLO testo semplice: la trascrizione usa add_text(), mai append_text() o BBCode, cosi' nessun tag,
## codice o comando generato viene interpretato. Indica sempre quale backend sta parlando (FINTO/LOCALE)
## e lo stato «in attesa / risposta / ripiego». Non tocca lo stato del gioco.
signal send_requested(text: String)
signal cancel_requested
signal close_requested

const Conversation := preload("res://addons/npc_ai/npc_conversation.gd")
const Service := preload("res://addons/npc_ai/npc_inference_service.gd")
const ACCENT := Color(1.0, 0.82, 0.5)
const DIM := Color(0.62, 0.6, 0.66)
const PLAYER_COLOR := Color(0.72, 0.85, 1.0)
const FALLBACK_COLOR := Color(1.0, 0.72, 0.55)
const NOTE_COLOR := Color(0.6, 0.85, 0.65)
const MAX_INPUT_CHARS := 240

var _name_lbl: Label
var _badge_lbl: Label
var _state_lbl: Label
var _transcript: RichTextLabel
var _stream_lbl: Label
var _input_edit: LineEdit
var _send_btn: Button
var _cancel_btn: Button
var _close_btn: Button
var _info_lbl: Label
var _conversation: RefCounted
var _service: Node


func _ready() -> void:
	_build()
	set_backend_badge("NESSUNO")
	set_state_text("Chiuso")


func bind(conversation: RefCounted, service: Node) -> void:
	unbind()
	_conversation = conversation
	_service = service
	_name_lbl.text = conversation.speaker_name()
	conversation.line_added.connect(_on_line_added)
	conversation.state_changed.connect(_on_state_changed)
	conversation.streaming_text.connect(show_stream)
	conversation.response_received.connect(_on_response_received)
	if service != null:
		service.state_changed.connect(_on_service_state)
		_on_service_state(service.state())
	clear()
	for line in conversation.transcript:
		_on_line_added(line["kind"], line["speaker"], line["text"])
	_on_state_changed(conversation.state)


func unbind() -> void:
	if _conversation != null:
		_conversation.line_added.disconnect(_on_line_added)
		_conversation.state_changed.disconnect(_on_state_changed)
		_conversation.streaming_text.disconnect(show_stream)
		_conversation.response_received.disconnect(_on_response_received)
	if _service != null and _service.state_changed.is_connected(_on_service_state):
		_service.state_changed.disconnect(_on_service_state)
	_conversation = null
	_service = null


func set_backend_badge(name: String) -> void:
	_badge_lbl.text = "backend: " + name
	_badge_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45) if name == "FINTO" else (Color(0.55, 0.9, 0.6) if name == "LOCALE" else DIM))


func set_state_text(text: String) -> void:
	_state_lbl.text = text


func set_info_text(text: String) -> void:
	_info_lbl.text = text


func clear() -> void:
	_transcript.clear()
	_stream_lbl.text = ""


func append_line(kind: String, speaker: String, text: String) -> void:
	var color := Color.WHITE
	var prefix := speaker
	match kind:
		"player": color = PLAYER_COLOR
		"npc_fallback", "npc_interrupted": color = FALLBACK_COLOR
		"note": color = NOTE_COLOR
		_: color = ACCENT
	if prefix != "":
		_transcript.push_color(color)
		_transcript.add_text(prefix + ": ")
		_transcript.pop()
		_transcript.add_text(text)
	else:
		_transcript.push_color(color)
		_transcript.add_text(text)
		_transcript.pop()
	if kind == "npc_fallback":
		_transcript.push_color(DIM)
		_transcript.add_text("  (ripiego)")
		_transcript.pop()
	elif kind == "npc_interrupted":
		_transcript.push_color(DIM)
		_transcript.add_text("  (interrotto)")
		_transcript.pop()
	_transcript.newline()
	_stream_lbl.text = ""


func show_stream(text_so_far: String) -> void:
	_stream_lbl.text = text_so_far


func focus_input() -> void:
	_input_edit.grab_focus()


func input_text() -> String:
	return _input_edit.text


func set_input_enabled(enabled: bool) -> void:
	_input_edit.editable = enabled
	_send_btn.disabled = not enabled


func _on_line_added(kind: String, speaker: String, text: String) -> void:
	append_line(kind, speaker, text)


func _on_state_changed(state: int) -> void:
	match state:
		Conversation.State.CLOSED:
			set_state_text("Chiuso")
			set_input_enabled(false)
			_cancel_btn.disabled = true
		Conversation.State.IDLE:
			set_state_text("Pronto")
			set_input_enabled(true)
			_cancel_btn.disabled = true
		Conversation.State.WAITING:
			set_state_text("In attesa…")
			set_input_enabled(false)
			_cancel_btn.disabled = false
		Conversation.State.RESPONDED:
			set_state_text("Risposta")
			set_input_enabled(true)
			_cancel_btn.disabled = true
		Conversation.State.FALLBACK:
			set_state_text("Ripiego")
			set_input_enabled(true)
			_cancel_btn.disabled = true
	if state != Conversation.State.CLOSED:
		focus_input()


func _on_service_state(state: int) -> void:
	match state:
		Service.ServiceState.NO_BACKEND: set_info_text("Nessun backend: solo battute scritte a mano.")
		Service.ServiceState.STARTING: set_info_text("Modello in caricamento… le risposte intanto sono di ripiego.")
		Service.ServiceState.READY: set_info_text("Modello pronto.")
		Service.ServiceState.BUSY: set_info_text("Il modello sta generando.")
		Service.ServiceState.FAILED: set_info_text("Modello non disponibile: dialogo in ripiego.")
		Service.ServiceState.STOPPED: set_info_text("Runtime fermato.")


func _on_response_received(response: RefCounted) -> void:
	var t: Dictionary = response.timings
	set_info_text("%s | %s | primo testo %d ms, totale %d ms, token %d%s" % [response.backend, response.model,
		int(t.get("first_token_msec", -1)), int(t.get("total_msec", 0)), int(t.get("tokens", 0)),
		("" if response.error_code == "" else " | " + response.error_code)])


func _submit() -> void:
	var text := _input_edit.text.strip_edges()
	if text == "":
		return
	_input_edit.text = ""
	send_requested.emit(text)


func _build() -> void:
	# set_anchors_preset da solo, con il controllo gia' nell'albero, ricalcola gli offset per conservare il
	# rettangolo corrente (0x0) e il pannello finisce fuori schermo: servono anche gli offset a zero.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.05, 0.08, 1.0)))   # opaco: nulla traspare da dietro
	box.anchor_left = 0.0
	box.anchor_top = 1.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 40
	box.offset_top = -330
	box.offset_right = -40
	box.offset_bottom = -24
	add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	box.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	vb.add_child(header)
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 22)
	_name_lbl.add_theme_color_override("font_color", ACCENT)
	header.add_child(_name_lbl)
	_badge_lbl = Label.new()
	_badge_lbl.add_theme_font_size_override("font_size", 14)
	header.add_child(_badge_lbl)
	_state_lbl = Label.new()
	_state_lbl.add_theme_font_size_override("font_size", 14)
	_state_lbl.add_theme_color_override("font_color", DIM)
	header.add_child(_state_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_close_btn = Button.new()
	_close_btn.text = "Chiudi"
	_close_btn.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close_btn)

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = false          # il testo generato non viene MAI interpretato
	_transcript.scroll_following = true
	_transcript.selection_enabled = true
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.add_theme_font_size_override("normal_font_size", 18)
	_transcript.add_theme_color_override("default_color", Color(0.93, 0.9, 0.85))
	vb.add_child(_transcript)

	_stream_lbl = Label.new()
	_stream_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stream_lbl.add_theme_font_size_override("font_size", 17)
	_stream_lbl.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	_stream_lbl.custom_minimum_size = Vector2(0, 24)
	vb.add_child(_stream_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Scrivi al fabbro (Invio per inviare)"
	_input_edit.max_length = MAX_INPUT_CHARS
	_input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	row.add_child(_input_edit)
	_send_btn = Button.new()
	_send_btn.text = "Invia"
	_send_btn.pressed.connect(_submit)
	row.add_child(_send_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Annulla"
	_cancel_btn.disabled = true
	_cancel_btn.pressed.connect(func() -> void: cancel_requested.emit())
	row.add_child(_cancel_btn)

	_info_lbl = Label.new()
	_info_lbl.add_theme_font_size_override("font_size", 13)
	_info_lbl.add_theme_color_override("font_color", DIM)
	vb.add_child(_info_lbl)


func _panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = Color(1.0, 0.82, 0.5, 0.35)
	s.set_content_margin_all(4)
	return s
