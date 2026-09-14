@tool
extends EditorPlugin

var map_export_busy := false
var panel: VBoxContainer
var scroll: ScrollContainer
var mode: OptionButton
var brush: SpinBox
var status: Label
var stream: Node3D
var camera: Camera3D
var dragging := false
var before: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var last := Vector3.INF
var stroke_target: Node3D
var rng := RandomNumberGenerator.new()
var strength: SpinBox
var seed_input: SpinBox
var stroke_method := "apply_edits"

func _enter_tree() -> void:
	add_custom_type("ProceduralRock","Node3D",preload("res://addons/rock_builder/rock.gd"),EditorInterface.get_base_control().get_theme_icon("MeshInstance3D","EditorIcons"))
	add_tool_menu_item("Crea roccia parametrica",_create_rock)
	add_tool_menu_item("Esporta mappa PNG · dall'alto",_choose_map_export.bind(false))
	add_tool_menu_item("Esporta mappa PNG · isometrica",_choose_map_export.bind(true))
	panel = VBoxContainer.new()
	scroll = ScrollContainer.new()
	scroll.name = "World"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	mode = OptionButton.new()
	for text in ["Navigate", "Place tree", "Paint forest", "Erase trees", "Raise terrain", "Lower terrain", "Flatten terrain", "Reserve POI zone"]: mode.add_item(text)
	panel.add_child(mode)
	var label := Label.new()
	label.text = "Brush radius (metres)"
	panel.add_child(label)
	brush = SpinBox.new()
	brush.min_value = 2
	brush.max_value = 50
	brush.value = 12
	panel.add_child(brush)
	strength = SpinBox.new()
	strength.prefix = "Height m "
	strength.min_value = -50
	strength.max_value = 50
	strength.step = 0.5
	strength.value = 2
	panel.add_child(strength)
	seed_input = SpinBox.new()
	seed_input.prefix = "Seed "
	seed_input.max_value = 2147483647
	seed_input.value = 2417
	panel.add_child(seed_input)
	var generate := Button.new()
	generate.text = "Regenerate procedural regions"
	generate.pressed.connect(_generate)
	panel.add_child(generate)
	var follow := CheckButton.new()
	follow.text = "Follow editor camera"
	follow.button_pressed = true
	follow.toggled.connect(func(value: bool):
		if is_instance_valid(stream): stream.follow_editor_camera = value)
	panel.add_child(follow)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 220
	panel.add_child(status)
	var map := preload("res://addons/world_editor/world_map.gd").new()
	map.plugin = self
	panel.add_child(map)
	var help := Label.new()
	help.text = "LMB: paint • RMB + WASD: fly\nCtrl+Z: undo • Ctrl+S: save scene\nMap click: preview region (camera stays in place)"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(help)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL,scroll)
	set_input_event_forwarding_always_enabled()
	set_process(true)

func _exit_tree() -> void:
	remove_custom_type("ProceduralRock"); remove_tool_menu_item("Crea roccia parametrica")
	remove_tool_menu_item("Esporta mappa PNG · dall'alto")
	remove_tool_menu_item("Esporta mappa PNG · isometrica")
	_finish()
	remove_control_from_docks(scroll)
	scroll.queue_free()

func _apply_changes() -> void:
	_finish()

func _handles(object: Object) -> bool:
	return object is Node3D

func _process(_delta: float) -> void:
	var root := EditorInterface.get_edited_scene_root()
	stream = root.get_node_or_null("Pixel/View/WorldStream") if root else null
	panel.visible = is_instance_valid(stream)
	if not is_instance_valid(stream): return
	if not is_instance_valid(camera): camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if stream.follow_editor_camera and is_instance_valid(camera):
		var origin := camera.global_position
		var direction := -camera.global_basis.z
		var focus := origin
		if direction.y < -0.05:
			focus = origin + direction * minf(-origin.y/direction.y, 3000.0)
		stream.editor_center = Vector2(clampf(focus.x,-850,850),clampf(focus.z,-850,850))
	status.text = "Preview: %.0f, %.0f\nLoaded cells: %d • edits: %d" % [stream.editor_center.x,stream.editor_center.y,stream._chunks.size(),stream.world_edits.size()]

func _forward_3d_gui_input(view_camera: Camera3D, event: InputEvent) -> int:
	camera = view_camera
	if not is_instance_valid(stream): return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		_finish()
		return AFTER_GUI_INPUT_STOP
	if mode.selected == 0: return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_finish()
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT: return AFTER_GUI_INPUT_PASS
	if not event is InputEventMouse: return AFTER_GUI_INPUT_PASS
	var ray := camera.project_ray_normal(event.position)
	var origin := camera.project_ray_origin(event.position)
	if absf(ray.y)<0.0001: return AFTER_GUI_INPUT_PASS
	var distance := -origin.y/ray.y
	if distance<0: return AFTER_GUI_INPUT_PASS
	var ground := stream.get_node_or_null("../Ground")
	var point := origin+ray*distance
	if ground and ground.has_method("ray_surface"):
		point = ground.ray_surface(origin, ray)
		if not point.is_finite(): return AFTER_GUI_INPUT_PASS
	if absf(point.x)>863 or absf(point.z)>863: return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		stroke_target = ground if mode.selected>=4 else stream
		stroke_method = "apply_zones" if mode.selected==7 else "apply_edits"
		var data: Array = ground.reserved_zones if mode.selected==7 else (ground.height_edits if mode.selected>=4 else stream.world_edits)
		before.assign(data.duplicate(true))
		pending.assign(before.duplicate(true))
		dragging = true
		last = Vector3.INF
		_stamp(point)
		return AFTER_GUI_INPUT_STOP
	if dragging and event is InputEventMouseMotion:
		if mode.selected != 1 and point.distance_to(last)>brush.value*0.6: _stamp(point)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _stamp(point: Vector3) -> void:
	last = point
	if mode.selected>=4:
		var radius := maxf(12.0,brush.value)
		if mode.selected==7:
			pending.append({"position":Vector2(point.x,point.z),"radius":radius})
		else:
			var value := strength.value if mode.selected==6 else absf(strength.value)*(1 if mode.selected==4 else -1)
			pending.append({"kind":"flatten" if mode.selected==6 else "offset","position":Vector2(point.x,point.z),"radius":radius,"value":value})
	elif mode.selected == 3:
		pending.append({"kind":"erase", "position":point, "radius":brush.value})
	else:
		var count := 1 if mode.selected == 1 else mini(80,maxi(1,int(PI*brush.value*brush.value/45.0)))
		for i in range(count):
			var p := point
			if mode.selected == 2:
				var angle := rng.randf()*TAU
				var r := sqrt(rng.randf())*brush.value
				p += Vector3(cos(angle),0,sin(angle))*r
			if absf(p.x)>863 or absf(p.z)>863: continue
			pending.append({"kind":"tree", "position":p, "scale":rng.randf_range(0.8,1.25)})
	# Terrain strokes rebuild once on release; tree preview remains live.
	if mode.selected<4: stroke_target.apply_edits(pending)

func _finish() -> void:
	if not dragging: return
	dragging = false
	if not is_instance_valid(stroke_target): return
	var undo := get_undo_redo()
	stroke_target.call(stroke_method,pending)
	undo.create_action("Edit world layer", UndoRedo.MERGE_DISABLE, stroke_target)
	undo.add_do_method(stroke_target,stroke_method,pending.duplicate(true))
	undo.add_undo_method(stroke_target,stroke_method,before.duplicate(true))
	undo.commit_action(false)
	EditorInterface.mark_scene_as_unsaved()

func _generate() -> void:
	_finish()
	if not is_instance_valid(stream): return
	var ground := stream.get_node("../Ground")
	var plan: Resource = preload("res://scripts/village/world_plan.gd").generate(int(seed_input.value))
	var undo := get_undo_redo()
	undo.create_action("Regenerate procedural regions",UndoRedo.MERGE_DISABLE,ground)
	undo.add_do_method(ground,"apply_plan",plan)
	undo.add_undo_method(ground,"apply_plan",ground.world_plan)
	undo.commit_action()
	EditorInterface.mark_scene_as_unsaved()

func _choose_map_export(isometric: bool) -> void:
	if map_export_busy: return
	var root := EditorInterface.get_edited_scene_root()
	if root==null: return
	var dialog := EditorFileDialog.new(); dialog.file_mode=EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access=EditorFileDialog.ACCESS_FILESYSTEM; dialog.add_filter("*.png","Mappa PNG")
	dialog.current_file=(root.scene_file_path.get_file().get_basename() if not root.scene_file_path.is_empty() else str(root.name))+("_isometrica.png" if isometric else "_alto.png")
	dialog.file_selected.connect(func(path):
		if map_export_busy: dialog.queue_free(); return
		var current := EditorInterface.get_edited_scene_root()
		if current==null: dialog.queue_free(); return
		var packed := PackedScene.new()
		if packed.pack(current)!=OK: dialog.queue_free(); return
		map_export_busy=true; dialog.queue_free()
		var progress := AcceptDialog.new(); progress.title="Esportazione mappa"
		progress.dialog_text="Caricamento della copia del mondo e acquisizione PNG…"; progress.get_ok_button().disabled=true
		EditorInterface.get_base_control().add_child(progress); progress.popup_centered()
		var result=await preload("res://addons/world_editor/map_export.gd").export_png(self,packed,path,isometric)
		map_export_busy=false
		if is_instance_valid(progress):
			progress.get_ok_button().disabled=false
			progress.dialog_text=result.get("error","PNG esportato: "+path)
			progress.confirmed.connect(progress.queue_free)
			progress.canceled.connect(progress.queue_free))
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog); dialog.popup_centered_ratio(0.65)

func _create_rock() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root==null: return
	var parent: Node=root.get_node_or_null("Pixel/View")
	if parent==null: parent=root
	var rock=preload("res://addons/rock_builder/rock.gd").new(); rock.name="Roccia"
	var undo := get_undo_redo(); undo.create_action("Crea roccia parametrica",UndoRedo.MERGE_DISABLE,root)
	undo.add_do_method(parent,"add_child",rock,true); undo.add_do_property(rock,"owner",root)
	undo.add_undo_method(parent,"remove_child",rock); undo.add_do_reference(rock); undo.commit_action()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(rock); EditorInterface.edit_node(rock)
