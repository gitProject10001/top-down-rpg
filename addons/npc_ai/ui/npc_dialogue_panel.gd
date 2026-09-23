extends Control
## Gameplay presentation of the same conversation API used by the lab.
signal send_requested(text: String)
signal cancel_requested
signal close_requested
var title: Label
var role: Label
var status: Label
var transcript: RichTextLabel
var entry: LineEdit
var send: Button
var cancel: Button
var topics_box: HBoxContainer
var frame: PanelContainer
var conversation: RefCounted
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame=PanelContainer.new(); add_child(frame)
	var style:=StyleBoxFlat.new(); style.bg_color=Color(.075,.061,.055,.97)
	style.border_color=Color(.55,.43,.27); style.set_border_width_all(2); style.set_corner_radius_all(8)
	style.content_margin_left=20; style.content_margin_right=20; style.content_margin_top=14; style.content_margin_bottom=14
	frame.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",8); frame.add_child(box)
	var header:=HBoxContainer.new(); box.add_child(header)
	title=Label.new(); title.add_theme_font_size_override("font_size",24); title.add_theme_color_override("font_color",Color(.94,.78,.49)); header.add_child(title)
	role=Label.new(); role.size_flags_horizontal=Control.SIZE_EXPAND_FILL; role.add_theme_color_override("font_color",Color(.7,.66,.57)); header.add_child(role)
	var close:=Button.new(); close.text="Chiudi · Esc"; close.pressed.connect(func(): close_requested.emit()); header.add_child(close)
	transcript=RichTextLabel.new(); transcript.custom_minimum_size.y=105; transcript.size_flags_vertical=Control.SIZE_EXPAND_FILL
	transcript.bbcode_enabled=false; transcript.scroll_following=true; transcript.add_theme_font_size_override("normal_font_size",18)
	transcript.add_theme_color_override("default_color",Color(.92,.88,.77)); box.add_child(transcript)
	status=Label.new(); status.add_theme_font_size_override("font_size",14); status.add_theme_color_override("font_color",Color(.75,.7,.6)); box.add_child(status)
	topics_box=HBoxContainer.new(); box.add_child(topics_box)
	var row:=HBoxContainer.new(); box.add_child(row)
	entry=LineEdit.new(); entry.placeholder_text="Scrivi una domanda…"; entry.max_length=240; entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	entry.text_submitted.connect(submit); row.add_child(entry)
	send=Button.new(); send.text="Invia ↵"; send.pressed.connect(func(): submit(entry.text)); row.add_child(send)
	cancel=Button.new(); cancel.text="Interrompi"; cancel.pressed.connect(func(): cancel_requested.emit()); row.add_child(cancel)
	resized.connect(layout); layout()
func layout() -> void:
	if not frame: return
	var width:=minf(760,size.x-32); var height:=minf(320,size.y-48)
	frame.position=Vector2((size.x-width)*.5,size.y-height-20); frame.size=Vector2(width,height)
func bind(value: RefCounted, profile: Resource, topics: PackedStringArray) -> void:
	unbind(); conversation=value
	title.text=profile.display_name; role.text="  ·  "+profile.trade
	transcript.clear()
	conversation.line_added.connect(on_line)
	conversation.streaming_text.connect(on_stream)
	for child in topics_box.get_children(): child.free()
	for topic in topics:
		var b:=Button.new(); b.text=topic; b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): send_requested.emit(topic)); topics_box.add_child(b)
	render_transcript()
	entry.text=""; entry.grab_focus()
func unbind() -> void:
	if conversation:
		if conversation.line_added.is_connected(on_line): conversation.line_added.disconnect(on_line)
		if conversation.streaming_text.is_connected(on_stream): conversation.streaming_text.disconnect(on_stream)
	conversation=null
func render_transcript(partial := "") -> void:
	transcript.clear()
	if not conversation: return
	for line in conversation.transcript:
		if line.kind!="npc_farewell": transcript.add_text(str(line.speaker)+": "+str(line.text)+"\n\n")
	if not partial.is_empty(): transcript.add_text(conversation.speaker_name()+": "+partial)
func on_line(_kind: String,_speaker: String,_text: String) -> void: render_transcript()
func on_stream(text: String) -> void: render_transcript(text)
func submit(text: String) -> void:
	if send.disabled or text.strip_edges().is_empty(): return
	send_requested.emit(text); entry.text=""
func update_status(waiting: bool,starting: bool,fallback: bool) -> void:
	status.text="Sta rispondendo…" if waiting else ("Un momento, si prepara a parlare…" if starting else ("Risposta breve disponibile; puoi continuare a parlare." if fallback else "Invio per parlare · Esc per tornare al borgo"))
	send.disabled=waiting or starting; entry.editable=not waiting and not starting
	cancel.disabled=not waiting
	for child in topics_box.get_children(): child.disabled=waiting or starting
