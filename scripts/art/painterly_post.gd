@tool
extends CanvasLayer
## Display-space painting pass plus camera-depth focus; HUD remains outside both.
@export var enabled := true:
	set(value):
		enabled=value
		if is_node_ready(): $Filter.visible=enabled
@export var depth_blur := false
@export_range(0.0, .3, .005) var blur_amount := .06
@export_range(.5, 30.0, .5) var near_clear := 6.0
@export_range(.5, 50.0, .5) var far_clear := 12.0
@export_range(.5, 30.0, .5) var focus_transition := 8.0
var panel: PanelContainer
var debug_layer: CanvasLayer
var _was_paused := false
var _camera: Camera3D
var _original_attributes: CameraAttributes
var _attributes: CameraAttributesPractical
const PARAMETERS := [
	["palette_strength","Palette ridotta",0.0,1.0,.01,.72],
	["soften_strength","Pennellate / ammorbidimento",0.0,1.0,.01,.6],
	["radius","Raggio del filtro",0.0,3.0,.05,1.25],
	["edge_preservation","Conservazione dei bordi",10.0,200.0,1.0,80.0],
	["warmth","Calore della palette",0.0,1.0,.01,.15]]
func _ready() -> void:
	$Filter.visible=enabled
	if Engine.is_editor_hint(): return
	process_mode=Node.PROCESS_MODE_ALWAYS
	_make_debug.call_deferred()
func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	if camera != _camera:
		if is_instance_valid(_camera): _camera.attributes=_original_attributes
		_camera=camera
		_original_attributes=camera.attributes
		_attributes=_original_attributes.duplicate(true) if _original_attributes is CameraAttributesPractical else CameraAttributesPractical.new()
		camera.attributes=_attributes
	var focus: Vector3=camera.get("_focus") if camera.get("_focus") is Vector3 else camera.global_position-camera.global_basis.z*40.0
	var distance := maxf(.1,(focus-camera.global_position).dot(-camera.global_basis.z))
	_attributes.dof_blur_near_enabled=depth_blur
	_attributes.dof_blur_far_enabled=depth_blur
	_attributes.dof_blur_amount=blur_amount
	_attributes.dof_blur_near_distance=maxf(.1,distance-near_clear)
	_attributes.dof_blur_far_distance=distance+far_clear
	_attributes.dof_blur_near_transition=focus_transition
	_attributes.dof_blur_far_transition=focus_transition
func _make_debug() -> void:
	debug_layer=CanvasLayer.new()
	debug_layer.layer=40
	debug_layer.process_mode=Node.PROCESS_MODE_ALWAYS
	get_window().add_child(debug_layer)
	panel=PanelContainer.new()
	var background:=StyleBoxFlat.new()
	background.bg_color=Color(.065,.075,.065,.98)
	background.content_margin_left=12
	background.content_margin_right=12
	background.content_margin_top=10
	background.content_margin_bottom=10
	panel.add_theme_stylebox_override("panel",background)
	panel.position=Vector2(16,70)
	panel.size=Vector2(385,minf(540,get_window().size.y-90))
	debug_layer.add_child(panel)
	var scroll:=ScrollContainer.new()
	panel.add_child(scroll)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.x=350
	scroll.add_child(box)
	var title:=Label.new();title.text="Resa pittorica e profondità";box.add_child(title)
	var toggle:=CheckButton.new();toggle.text="Filtro pittorico";toggle.button_pressed=enabled;box.add_child(toggle)
	toggle.toggled.connect(func(v:bool):enabled=v)
	for entry in PARAMETERS:
		var value=$Filter.material.get_shader_parameter(entry[0])
		_slider(box,entry[1],entry[2],entry[3],entry[4],float(value) if value!=null else entry[5],func(v:float):$Filter.material.set_shader_parameter(entry[0],v))
	var dof:=CheckButton.new();dof.text="Profondità di campo";dof.button_pressed=depth_blur;box.add_child(dof)
	dof.toggled.connect(func(v:bool):depth_blur=v)
	_slider(box,"Intensità sfocatura",0,.3,.005,blur_amount,func(v:float):blur_amount=v)
	_slider(box,"Primo piano nitido (metri)",.5,30,.5,near_clear,func(v:float):near_clear=v)
	_slider(box,"Sfondo nitido (metri)",.5,50,.5,far_clear,func(v:float):far_clear=v)
	_slider(box,"Transizione morbida (metri)",.5,30,.5,focus_transition,func(v:float):focus_transition=v)
	var note:=Label.new();note.text="Fuoco segue il personaggio. UI sempre nitida.\nModifiche di prova per questa sessione.";box.add_child(note)
	var close:=Button.new();close.text="Chiudi · P / Esc";box.add_child(close);close.pressed.connect(func():set_panel_open(false))
	panel.hide()
func _slider(box: VBoxContainer,label: String,lo:float,hi:float,step:float,value:float,changed:Callable) -> void:
	var text:=Label.new();box.add_child(text)
	var slider:=HSlider.new();slider.min_value=lo;slider.max_value=hi;slider.step=step;slider.value=value;box.add_child(slider)
	text.text="%s: %.2f"%[label,value]
	slider.value_changed.connect(func(v:float):text.text="%s: %.2f"%[label,v];changed.call(v))
func set_panel_open(value:bool) -> void:
	if not is_instance_valid(panel) or panel.visible==value:return
	if value:
		_was_paused=get_tree().paused
		get_tree().paused=true
	else:get_tree().paused=_was_paused
	panel.visible=value
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_P:
			if is_instance_valid(panel): set_panel_open(not panel.visible)
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE and is_instance_valid(panel) and panel.visible:
			set_panel_open(false)
			get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	if Engine.is_editor_hint():return
	if is_instance_valid(panel) and panel.visible:get_tree().paused=_was_paused
	if is_instance_valid(_camera):_camera.attributes=_original_attributes
	if is_instance_valid(debug_layer):debug_layer.queue_free()
