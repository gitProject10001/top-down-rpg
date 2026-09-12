@tool
extends EditorPlugin
const Village=preload("res://addons/village_builder/village.gd")
const Guide=preload("res://addons/village_builder/guide.gd")
const Lot=preload("res://addons/village_builder/lot.gd")
var panel: ScrollContainer
var tabs: TabContainer
var status: Label
var dialog: AcceptDialog
var gizmos: EditorNode3DGizmoPlugin
var mode := -1
var draft: Node3D
var selected: Node3D
var _test_runner: RefCounted
var road_width: SpinBox
var zone_type: OptionButton
var floors: SpinBox
func _enter_tree() -> void:
	gizmos=preload("res://addons/village_builder/gizmo.gd").new(); gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(gizmos)
	panel=ScrollContainer.new(); panel.name="Villaggio"; panel.custom_minimum_size.x=280; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_child(column)
	var create := Button.new(); create.text="Crea villaggio"; create.pressed.connect(_create); column.add_child(create)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text="Crea un villaggio, poi disegna perimetro, strade e zone."; column.add_child(status)
	tabs=TabContainer.new(); column.add_child(tabs)
	for i in 3:
		var page := VBoxContainer.new(); page.name=["Area","Strade","Lotti"][i]; tabs.add_child(page)
		var help := Label.new(); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; help.text=["Definisci il confine del villaggio.","Disegna percorsi a segmenti. Regola Road Width nell'Inspector.","Disegna zone edificabili. Building Type e Storeys regolano le case della zona."][i]; page.add_child(help)
		var draw := Button.new(); draw.text=["Disegna perimetro","Disegna strada","Disegna zona edificabile"][i]; draw.pressed.connect(_draw.bind(i)); page.add_child(draw)
		var select := Button.new(); select.text="Seleziona / modifica punti"; select.pressed.connect(_cancel); page.add_child(select)
		var point := Button.new(); point.text="Aggiungi punto sul lato più lungo"; point.pressed.connect(_add_point); page.add_child(point)
		var remove := Button.new(); remove.text="Rimuovi ultimo punto"; remove.pressed.connect(_remove_point); page.add_child(remove)
	var generate := Button.new(); generate.text="Genera / aggiorna lotti e case"; generate.pressed.connect(_generate); tabs.get_child(2).add_child(generate)
	road_width=SpinBox.new(); road_width.prefix="Larghezza strada"; road_width.suffix="m"; road_width.min_value=2; road_width.max_value=10; road_width.step=0.25; road_width.value=3
	road_width.value_changed.connect(func(v): _guide_property("road_width",v)); tabs.get_child(1).add_child(road_width)
	zone_type=OptionButton.new()
	for title in ["Casa popolana","Bottega","Casa benestante"]: zone_type.add_item(title)
	zone_type.item_selected.connect(func(v): _guide_property("building_type",v)); tabs.get_child(2).add_child(zone_type); tabs.get_child(2).move_child(zone_type,1)
	floors=SpinBox.new(); floors.prefix="Piani"; floors.min_value=1; floors.max_value=3; floors.step=1
	floors.value_changed.connect(func(v): _guide_property("storeys",int(v))); tabs.get_child(2).add_child(floors); tabs.get_child(2).move_child(floors,2)
	var lock := Button.new(); lock.text="Blocca / sblocca lotto selezionato"; lock.pressed.connect(_lock); tabs.get_child(2).add_child(lock)
	var tip := Label.new(); tip.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; tip.text="Disegno: clic per aggiungere punti · Invio per confermare · Esc per annullare.\nSolo la guida selezionata mostra le maniglie.\nPrima versione: layout su terreno piano."; column.add_child(tip)
	dialog=AcceptDialog.new(); dialog.title="Villaggio · operazione non eseguita"; dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; dialog.get_label().custom_minimum_size.x=440; EditorInterface.get_base_control().add_child(dialog)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL,panel)
	EditorInterface.get_selection().selection_changed.connect(_selection)
	tabs.tab_changed.connect(_tab_changed); set_input_event_forwarding_always_enabled()
	if "--village-editor-test" in OS.get_cmdline_user_args():
		_test_runner=load("res://tools/check_village_editor.gd").new(); _test_runner.call_deferred("run",self)
func _exit_tree() -> void:
	_cancel(); EditorInterface.get_selection().selection_changed.disconnect(_selection)
	remove_node_3d_gizmo_plugin(gizmos); remove_control_from_docks(panel); panel.queue_free(); dialog.queue_free()
func _handles(object: Object) -> bool: return object is Village or object is Guide or object is Lot or mode>=0
func _village() -> Node3D:
	for node in EditorInterface.get_selection().get_selected_nodes():
		var ancestor: Node=node
		while ancestor!=null:
			if ancestor is Village: return ancestor
			ancestor=ancestor.get_parent()
	return selected if is_instance_valid(selected) else null
func _selection() -> void:
	gizmos.focus=null
	var village := _village()
	if village: selected=village
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Village or node is Guide or node is Lot: _show_context_dock.call_deferred()
		if node is Guide:
			gizmos.focus=node; tabs.current_tab=node.kind; status.text="Guida: "+str(node.name)
			road_width.set_block_signals(true); road_width.value=node.road_width; road_width.set_block_signals(false)
			zone_type.select(node.building_type); floors.set_block_signals(true); floors.value=node.storeys; floors.set_block_signals(false)
	road_width.editable=is_instance_valid(gizmos.focus) and gizmos.focus.kind==1
	zone_type.disabled=not is_instance_valid(gizmos.focus) or gizmos.focus.kind!=2
	floors.editable=is_instance_valid(gizmos.focus) and gizmos.focus.kind==2
	if village:
		for child in village.get_children():
			if child is Guide: child.update_gizmos()
func _show_context_dock() -> void:
	var ancestor: Node=panel.get_parent()
	while ancestor!=null:
		if ancestor is EditorDock: ancestor.make_visible(); return
		ancestor=ancestor.get_parent()
func _guide_property(key: String,value: Variant) -> void:
	if not is_instance_valid(gizmos.focus): return
	var node=gizmos.focus
	if node.get(key)==value: return
	var undo := get_undo_redo(); undo.create_action("Impostazione guida",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,key,value); undo.add_undo_property(node,key,node.get(key)); undo.commit_action()
func _tab_changed(index: int) -> void:
	_cancel()
	if is_instance_valid(gizmos.focus) and gizmos.focus.kind!=index:
		var old=gizmos.focus; gizmos.focus=null; old.update_gizmos()
func _error(message: String) -> void:
	status.text=message; dialog.dialog_text=message; dialog.popup_centered(Vector2i(500,200))
func _create() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root==null: _error("Apri una scena prima di creare il villaggio."); return
	var parent: Node=root.get_node("Pixel/View") if root.has_node("Pixel/View") else root
	var node := Village.new(); node.name="Villaggio"; _add(parent,node,"Crea villaggio"); selected=node
func _attach(parent: Node,node: Node) -> void:
	parent.add_child(node,true); node.owner=EditorInterface.get_edited_scene_root()
func _add(parent: Node,node: Node,label: String) -> void:
	var undo := get_undo_redo(); undo.create_action(label,UndoRedo.MERGE_DISABLE,parent)
	undo.add_do_method(self,"_attach",parent,node); undo.add_undo_method(parent,"remove_child",node); undo.add_do_reference(node); undo.commit_action()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(node); EditorInterface.edit_node(node)
func _draw(kind: int) -> void:
	_cancel()
	var village := _village()
	if village==null: _error("Crea o seleziona un villaggio."); return
	if kind==0 and not village.guides(0).is_empty(): _error("Il perimetro esiste già: selezionalo nell'albero e trascina i suoi punti."); return
	for other in get_parent().get_children():
		if other==self or other.get_script()==null: continue
		if other.get_script().resource_path=="res://addons/house_builder/plugin.gd": other._set_mode(0)
		if other.get_script().resource_path=="res://addons/world_editor/plugin.gd" and is_instance_valid(other.mode): other.mode.select(0)
	mode=kind; draft=Guide.new(); draft.kind=kind; draft.points=PackedVector2Array(); draft.name=["Perimetro","Strada","Zona"][kind]; draft.stable_id="guide_%d"%Time.get_ticks_usec(); village.add_child(draft)
	gizmos.focus=draft; status.text="Clicca i vertici sul terreno. Invio conferma; Esc annulla."
func _cancel() -> void:
	mode=-1
	if is_instance_valid(draft): draft.queue_free()
	draft=null
func _forward_3d_gui_input(camera: Camera3D,event: InputEvent) -> int:
	if mode<0: return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: _cancel(); return AFTER_GUI_INPUT_STOP
		if event.keycode==KEY_ENTER or event.keycode==KEY_KP_ENTER:
			if draft.points.size()<(2 if mode==1 else 3): _error("Aggiungi almeno due punti per una strada, tre per un'area."); return AFTER_GUI_INPUT_STOP
			var node := draft; var parent := node.get_parent(); parent.remove_child(node); draft=null; mode=-1; _add(parent,node,"Disegna guida villaggio"); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var inverse: Transform3D=draft.global_transform.affine_inverse()
		var point=Plane(Vector3.UP,0).intersects_ray(inverse*camera.project_ray_origin(event.position),inverse.basis*camera.project_ray_normal(event.position))
		if point!=null:
			var points: PackedVector2Array=draft.points.duplicate(); points.append(Vector2(snappedf(point.x,0.5),snappedf(point.z,0.5))); draft.points=points
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS
func _edit_points(points: PackedVector2Array) -> void:
	var node=gizmos.focus; var undo := get_undo_redo(); undo.create_action("Modifica punti guida",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,"points",points); undo.add_undo_property(node,"points",node.points); undo.commit_action()
func _add_point() -> void:
	if not is_instance_valid(gizmos.focus): _error("Seleziona una guida nella scheda attiva."); return
	var node=gizmos.focus; var points: PackedVector2Array=node.points.duplicate(); var best := -1; var length := 0.0
	for i in range(points.size()-(1 if node.kind==1 else 0)):
		var distance := points[i].distance_to(points[(i+1)%points.size()])
		if distance>length: length=distance; best=i
	if best>=0: points.insert(best+1,(points[best]+points[(best+1)%points.size()])*0.5); _edit_points(points)
func _remove_point() -> void:
	if not is_instance_valid(gizmos.focus): return
	var node=gizmos.focus; var points: PackedVector2Array=node.points.duplicate()
	if points.size()<=(2 if node.kind==1 else 3): _error("La guida ha già il numero minimo di punti."); return
	points.remove_at(points.size()-1); _edit_points(points)
func _generate() -> void:
	var village := _village()
	if village==null: _error("Seleziona un villaggio."); return
	var before: Array=village.snapshot(); var after: Array=village.propose()
	if village.failed: _error(village.report); return
	var undo := get_undo_redo(); undo.create_action("Genera lotti e case",UndoRedo.MERGE_DISABLE,village)
	undo.add_do_method(village,"apply",after); undo.add_undo_method(village,"apply",before); undo.commit_action(); status.text=village.report
func _lock() -> void:
	for node in EditorInterface.get_selection().get_selected_nodes():
		var lot: Node=node
		while lot!=null and not lot is Lot: lot=lot.get_parent()
		if lot is Lot:
			var undo := get_undo_redo(); undo.create_action("Proteggi lotto",UndoRedo.MERGE_DISABLE,lot)
			undo.add_do_property(lot,"locked",not lot.locked); undo.add_undo_property(lot,"locked",lot.locked); undo.commit_action(); return
	_error("Seleziona un lotto o la sua casa.")
