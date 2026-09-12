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
var drawing_actions: HBoxContainer
var drawing_camera: Camera3D
var cursor_point := Vector3.ZERO
var cursor_visible := false
var preview_draw_count := 0
var brush_radius: SpinBox
var brush_target: SpinBox
var paint_before: Dictionary = {}
var paint_village: Node3D
var painting := false
func _enter_tree() -> void:
	gizmos=preload("res://addons/village_builder/gizmo.gd").new(); gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(gizmos)
	panel=ScrollContainer.new(); panel.name="Villaggio"; panel.custom_minimum_size.x=360; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_child(column)
	var create := Button.new(); create.text="Crea villaggio"; create.pressed.connect(_create); column.add_child(create)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text="Crea un villaggio, poi disegna perimetro e strade. Tutta l’area è edificabile."; column.add_child(status)
	drawing_actions=HBoxContainer.new(); drawing_actions.hide(); column.add_child(drawing_actions)
	var confirm := Button.new(); confirm.text="Conferma disegno"; confirm.pressed.connect(_finish_drawing); drawing_actions.add_child(confirm)
	var cancel := Button.new(); cancel.text="Annulla"; cancel.pressed.connect(_cancel); drawing_actions.add_child(cancel)
	tabs=TabContainer.new(); column.add_child(tabs)
	for i in 3:
		var page := VBoxContainer.new(); page.name=["Area","Strade","Vincoli"][i]; tabs.add_child(page)
		var help := Label.new(); help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; help.text=["Definisci il confine del villaggio.","Disegna percorsi a segmenti. Regola Road Width nell'Inspector.","Tutto il perimetro è edificabile. Escludi piazze e spazi liberi; i quartieri sono opzionali."][i]; page.add_child(help)
		var draw := Button.new(); draw.text=["Disegna perimetro","Disegna strada","Disegna area non edificabile"][i]; draw.pressed.connect(_draw.bind(3 if i==2 else i)); page.add_child(draw)
		var select := Button.new(); select.text="Seleziona / modifica punti"; select.pressed.connect(_cancel); page.add_child(select)
		var point := Button.new(); point.text="Aggiungi punto sul lato più lungo"; point.pressed.connect(_add_point); page.add_child(point)
		var remove := Button.new(); remove.text="Rimuovi ultimo punto"; remove.pressed.connect(_remove_point); page.add_child(remove)
	var generate := Button.new(); generate.text="Genera / aggiorna lotti e case"; generate.pressed.connect(_generate); column.add_child(generate)
	road_width=SpinBox.new(); road_width.prefix="Larghezza strada"; road_width.suffix="m"; road_width.min_value=2; road_width.max_value=10; road_width.step=0.25; road_width.value=3
	road_width.value_changed.connect(func(v): _guide_property("road_width",v)); tabs.get_child(1).add_child(road_width)
	zone_type=OptionButton.new()
	for title in ["Casa popolana","Bottega","Casa benestante"]: zone_type.add_item(title)
	zone_type.item_selected.connect(func(v): _guide_property("building_type",v)); tabs.get_child(2).add_child(zone_type); tabs.get_child(2).move_child(zone_type,1)
	floors=SpinBox.new(); floors.prefix="Piani"; floors.min_value=1; floors.max_value=3; floors.step=1
	floors.value_changed.connect(func(v): _guide_property("storeys",int(v))); tabs.get_child(2).add_child(floors); tabs.get_child(2).move_child(floors,2)
	var district := Button.new(); district.text="Disegna quartiere (tipo di casa)"; district.pressed.connect(_draw.bind(2)); tabs.get_child(2).add_child(district)
	var density_page := VBoxContainer.new(); density_page.name="Densità"; tabs.add_child(density_page)
	var explanation := Label.new(); explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; explanation.text="Dipingi quante case proporre: 0% nessuna, 100% massimo. Poi Genera / aggiorna. Le case modificate restano protette."; density_page.add_child(explanation)
	brush_radius=SpinBox.new(); brush_radius.prefix="Raggio"; brush_radius.suffix="m"; brush_radius.min_value=2; brush_radius.max_value=30; brush_radius.value=6; density_page.add_child(brush_radius)
	brush_target=SpinBox.new(); brush_target.prefix="Densità"; brush_target.suffix="%"; brush_target.max_value=100; brush_target.step=5; brush_target.value=0; density_page.add_child(brush_target)
	var paint := Button.new(); paint.text="Dipingi densità"; paint.pressed.connect(_begin_paint); density_page.add_child(paint)
	var stop := Button.new(); stop.text="Termina pennello"; stop.pressed.connect(_cancel); density_page.add_child(stop)
	for value in [0.0,1.0]:
		var reset := Button.new(); reset.text="Tutto vuoto" if value==0 else "Densità massima ovunque"; reset.pressed.connect(_reset_density.bind(value)); density_page.add_child(reset)
	var group_page := VBoxContainer.new(); group_page.name="Gruppi"; tabs.add_child(group_page)
	var group_help := Label.new(); group_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; group_help.text="Disegna lo spazio libero della corte: il builder dispone edifici di dimensioni diverse intorno ai suoi lati e collega le porte alle strade. Sposta la corte e rigenera per spostare il gruppo. Tipo e piani sono nell’Inspector della corte."; group_page.add_child(group_help)
	var organic := Button.new(); organic.text="Usa disposizione per gruppi"; organic.pressed.connect(_organic_mode); group_page.add_child(organic)
	var court := Button.new(); court.text="Disegna corte"; court.pressed.connect(_draw.bind(4)); group_page.add_child(court)
	var group_lock := Button.new(); group_lock.text="Blocca / sblocca gruppo selezionato"; group_lock.pressed.connect(_lock_group); group_page.add_child(group_lock)
	var surface := Button.new(); surface.text="Attiva / disattiva suolo automatico"; surface.pressed.connect(_toggle_surface); group_page.add_child(surface)
	var zones := Button.new(); zones.text="Mostra / nascondi zone"; zones.pressed.connect(_toggle_zones); column.add_child(zones)
	var play := Button.new(); play.text="▶ Play villaggio selezionato"; play.pressed.connect(_play_selected); column.add_child(play)
	var lock := Button.new(); lock.text="Blocca / sblocca lotto selezionato"; lock.pressed.connect(_lock); tabs.get_child(2).add_child(lock)
	var tip := Label.new(); tip.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; tip.text="Disegno: clic per aggiungere punti · Invio per confermare · Esc per annullare.\nSolo la guida selezionata mostra le maniglie.\nPrima versione: layout su terreno piano."; column.add_child(tip)
	dialog=AcceptDialog.new(); dialog.title="Villaggio · operazione non eseguita"; dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; dialog.get_label().custom_minimum_size.x=440; EditorInterface.get_base_control().add_child(dialog)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL,panel)
	EditorInterface.get_selection().selection_changed.connect(_selection)
	tabs.tab_changed.connect(_tab_changed); set_input_event_forwarding_always_enabled()
	scene_changed.connect(_scene_changed)
	set_process(true)
	if "--village-editor-test" in OS.get_cmdline_user_args():
		_test_runner=load("res://tools/check_village_editor.gd").new(); _test_runner.call_deferred("run",self)
func _exit_tree() -> void:
	_cancel(); EditorInterface.get_selection().selection_changed.disconnect(_selection)
	remove_node_3d_gizmo_plugin(gizmos); remove_control_from_docks(panel); panel.queue_free(); dialog.queue_free()
func _handles(object: Object) -> bool: return object is Village or object is Guide or object is Lot or mode>=0
func _in_current_scene(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion(): return false
	var root := EditorInterface.get_edited_scene_root()
	return root!=null and (node==root or root.is_ancestor_of(node))
func _scene_changed(_root: Node) -> void:
	_cancel(); selected=null; _selection()
func _process(_dt: float) -> void:
	if (selected!=null and not _in_current_scene(selected)) or (draft!=null and not _in_current_scene(draft)):
		_cancel(); selected=null; _selection()
func _village() -> Node3D:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if not _in_current_scene(node): continue
		var ancestor: Node=node
		while ancestor!=null:
			if ancestor is Village and _in_current_scene(ancestor): return ancestor
			ancestor=ancestor.get_parent()
	return selected if _in_current_scene(selected) else null
func _selection() -> void:
	gizmos.focus=null
	var village := _village()
	selected=village
	if village==null: status.text="Nessun villaggio attivo. Premi Crea villaggio, poi Disegna perimetro."
	for node in EditorInterface.get_selection().get_selected_nodes():
		if not _in_current_scene(node): continue
		if node is Village or node is Guide or node is Lot: _show_context_dock.call_deferred()
		if node is Guide:
			gizmos.focus=node; tabs.current_tab=(4 if node.kind==4 else mini(node.kind,2)); status.text="Guida: "+str(node.name)
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
	if is_instance_valid(gizmos.focus) and (4 if gizmos.focus.kind==4 else mini(gizmos.focus.kind,2))!=index:
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
	mode=kind; draft=Guide.new(); draft.kind=kind; draft.points=PackedVector2Array(); draft.name=["Perimetro","Strada","Quartiere","AreaLibera","Corte"][kind]; draft.stable_id="guide_%d"%Time.get_ticks_usec(); village.add_child(draft)
	gizmos.focus=draft; status.text="Clicca i vertici sul terreno. Invio conferma; Esc annulla."
	drawing_actions.show(); cursor_visible=false; update_overlays()
func _finish_drawing() -> void:
	if not _in_current_scene(draft): _cancel(); return
	if draft.points.size()<(2 if mode==1 else 3): _error("Aggiungi almeno due punti per una strada, tre per un'area."); return
	if mode!=1 and Geometry2D.triangulate_polygon(draft.points).is_empty(): _error("Il contorno non è valido: evita punti coincidenti e lati incrociati."); return
	var node := draft; var parent := node.get_parent(); parent.remove_child(node); draft=null; mode=-1
	drawing_actions.hide(); cursor_visible=false; update_overlays()
	_add(parent,node,"Disegna guida villaggio"); status.text=str(node.name)+" creato. Seleziona la guida per spostare i punti."
func _cancel() -> void:
	if painting and is_instance_valid(paint_village): paint_village.density_state=paint_before
	painting=false; paint_before={}; paint_village=null
	mode=-1
	cursor_visible=false
	if is_instance_valid(drawing_actions): drawing_actions.hide()
	if is_instance_valid(draft):
		if gizmos.focus==draft: gizmos.focus=null
		if draft.get_parent()!=null: draft.get_parent().remove_child(draft)
		draft.queue_free()
	draft=null
	update_overlays()
func _forward_3d_gui_input(camera: Camera3D,event: InputEvent) -> int:
	drawing_camera=camera
	if tabs.current_tab==3: update_overlays()
	if mode==5: return _paint_input(camera,event)
	if mode<0: return AFTER_GUI_INPUT_PASS
	if not _in_current_scene(draft): _cancel(); return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE: _cancel(); return AFTER_GUI_INPUT_STOP
		if event.keycode==KEY_ENTER or event.keycode==KEY_KP_ENTER:
			_finish_drawing(); return AFTER_GUI_INPUT_STOP
		if event.keycode==KEY_BACKSPACE:
			var points: PackedVector2Array=draft.points.duplicate()
			if not points.is_empty(): points.remove_at(points.size()-1); draft.points=points; update_overlays()
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT):
		drawing_camera=camera
		var inverse: Transform3D=draft.global_transform.affine_inverse()
		var point=Plane(Vector3.UP,0).intersects_ray(inverse*camera.project_ray_origin(event.position),inverse.basis*camera.project_ray_normal(event.position))
		if point!=null:
			cursor_point=Vector3(snappedf(point.x,0.5),0,snappedf(point.z,0.5)); cursor_visible=true
			if event is InputEventMouseButton:
				var points: PackedVector2Array=draft.points.duplicate(); var p := Vector2(cursor_point.x,cursor_point.z)
				if points.is_empty() or not points[-1].is_equal_approx(p): points.append(p); draft.points=points
			status.text="Disegno attivo · %d punti. Clic per aggiungere; Invio o Conferma disegno per finire."%draft.points.size()
		else: cursor_visible=false
		update_overlays()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if tabs.current_tab==3 and is_instance_valid(drawing_camera): _draw_density(overlay)
	if mode==5: return
	if mode<0 or not _in_current_scene(draft) or not is_instance_valid(drawing_camera): return
	preview_draw_count+=1
	var points := PackedVector2Array()
	for p in draft.points: points.append(drawing_camera.unproject_position(draft.to_global(Vector3(p.x,0,p.y))))
	var color: Color=[Color(0.35,1,0.5),Color(1,0.8,0.25),Color(0.35,0.75,1),Color(1,0.3,0.15),Color(1,0.8,0.4)][mode]
	var outline := points.duplicate()
	var cursor := drawing_camera.unproject_position(draft.to_global(cursor_point))
	if cursor_visible and (outline.is_empty() or outline[-1].distance_to(cursor)>1): outline.append(cursor)
	if mode!=1 and outline.size()>2:
		if not Geometry2D.triangulate_polygon(outline).is_empty(): overlay.draw_colored_polygon(outline,Color(color,0.15))
		outline.append(outline[0])
	if outline.size()>1: overlay.draw_polyline(outline,color,3.0,true)
	for i in points.size():
		overlay.draw_circle(points[i],6,Color.BLACK); overlay.draw_circle(points[i],4,color)
		overlay.draw_string(overlay.get_theme_default_font(),points[i]+Vector2(9,-9),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
	if cursor_visible:
		overlay.draw_line(cursor-Vector2(9,0),cursor+Vector2(9,0),color,2)
		overlay.draw_line(cursor-Vector2(0,9),cursor+Vector2(0,9),color,2)
	overlay.draw_style_box(overlay.get_theme_stylebox("panel","Panel"),Rect2(12,50,560,34))
	overlay.draw_string(overlay.get_theme_default_font(),Vector2(22,73),"DISEGNO · Clic: punto · Invio: conferma · Backspace: elimina · Esc: annulla",HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
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

func _begin_paint() -> void:
	_cancel()
	paint_village=_village()
	if paint_village==null or paint_village.guides(0).is_empty(): _error("Crea prima il perimetro del villaggio."); return
	for other in get_parent().get_children():
		if other==self or other.get_script()==null: continue
		if other.get_script().resource_path=="res://addons/house_builder/plugin.gd": other._set_mode(0)
		if other.get_script().resource_path=="res://addons/world_editor/plugin.gd" and is_instance_valid(other.mode): other.mode.select(0)
	mode=5; status.text="Trascina con il tasto sinistro. Esc termina; annulla la pennellata in corso. Poi Genera / aggiorna."
	update_overlays()
func _density_action(node: Node,before: Dictionary,after: Dictionary) -> void:
	var undo := get_undo_redo(); undo.create_action("Dipingi densità",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,"density_state",after); undo.add_undo_property(node,"density_state",before)
	undo.add_do_method(self,"update_overlays"); undo.add_undo_method(self,"update_overlays"); undo.commit_action()
func _reset_density(value: float) -> void:
	_cancel()
	var node := _village()
	if node==null: _error("Seleziona un villaggio."); return
	_density_action(node,node.density_state.duplicate(true),{"base":value,"cells":{}})
func _paint_input(camera: Camera3D,event: InputEvent) -> int:
	if not _in_current_scene(paint_village): _cancel(); return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: _cancel(); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT):
		var inverse := paint_village.global_transform.affine_inverse()
		var point=Plane(Vector3.UP,0).intersects_ray(inverse*camera.project_ray_origin(event.position),inverse.basis*camera.project_ray_normal(event.position))
		var previous := cursor_point
		if point!=null: cursor_point=point; cursor_visible=true
		else: cursor_visible=false
		if event is InputEventMouseButton:
			if event.pressed: paint_before=paint_village.density_state.duplicate(true); painting=true; previous=cursor_point
			elif painting:
				painting=false; _density_action(paint_village,paint_before,paint_village.density_state.duplicate(true)); paint_before={}
		if painting and cursor_visible:
			var steps := maxi(1,ceili(previous.distance_to(cursor_point)/1.0))
			for i in range(1,steps+1):
				var p := previous.lerp(cursor_point,float(i)/steps)
				paint_village.paint_density(Vector2(p.x,p.z),brush_radius.value,brush_target.value/100.0)
		update_overlays(); return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS
func _draw_density(overlay: Control) -> void:
	var node := _village()
	if node==null or node.guides(0).is_empty(): return
	var boundary: PackedVector2Array=node.guides(0)[0].village_points()
	if boundary.size()<3: return
	var bounds := Rect2(boundary[0],Vector2.ZERO)
	for point in boundary: bounds=bounds.expand(point)
	var cell := maxf(2.0,ceilf(maxf(bounds.size.x,bounds.size.y)/64.0))
	for x in range(floori(bounds.position.x/cell),ceili(bounds.end.x/cell)):
		for y in range(floori(bounds.position.y/cell),ceili(bounds.end.y/cell)):
			var center := (Vector2(x,y)+Vector2.ONE*0.5)*cell
			if not Geometry2D.is_point_in_polygon(center,boundary): continue
			var quad := PackedVector2Array()
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var p: Vector2=(Vector2(x,y)+corner)*cell
				quad.append(drawing_camera.unproject_position(node.to_global(Vector3(p.x,0,p.y))))
			overlay.draw_colored_polygon(quad,Color(0.8,0.15,0.08,0.24).lerp(Color(0.15,0.9,0.3,0.24),node.density_at(center)))
	if mode==5 and cursor_visible:
		var ring := PackedVector2Array()
		for i in 33:
			var angle := TAU*i/32.0
			ring.append(drawing_camera.unproject_position(node.to_global(cursor_point+Vector3(cos(angle),0,sin(angle))*brush_radius.value)))
		overlay.draw_polyline(ring,Color.WHITE,2,true)

func _organic_mode() -> void:
	var node := _village()
	if node==null: _error("Seleziona un villaggio."); return
	var undo := get_undo_redo(); undo.create_action("Disposizione per gruppi",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,"layout_mode",1); undo.add_undo_property(node,"layout_mode",node.layout_mode); undo.commit_action()
	status.text="Modalità gruppi attiva. Disegna le corti, poi Genera / aggiorna."
func _play_selected() -> void:
	var village := _village()
	if village==null or village.lots().is_empty(): _error("Seleziona un villaggio con case generate."); return
	var packed := _snapshot_village(village)
	var error := ResourceSaver.save(packed,"user://village_builder_playtest.tscn") if packed else ERR_CANT_CREATE
	if error!=OK: _error("Impossibile preparare il villaggio per Play: "+error_string(error)); return
	EditorInterface.play_custom_scene("res://scenes/dev/village_organic_playable.tscn")
func _snapshot_village(village: Node3D) -> PackedScene:
	var copy := village.duplicate(); copy.transform=Transform3D.IDENTITY
	_set_preview_owner(copy,copy)
	var packed := PackedScene.new(); var error := packed.pack(copy); copy.free()
	return packed if error==OK else null
func _set_preview_owner(node: Node,root: Node) -> void:
	if node!=root: node.owner=root
	for child in node.get_children(): _set_preview_owner(child,root)

func _lock_group() -> void:
	if not is_instance_valid(gizmos.focus) or gizmos.focus.kind!=4: _error("Seleziona una corte per bloccare il gruppo."); return
	_guide_property("locked",not gizmos.focus.locked)
	status.text="Gruppo bloccato: le sue case saranno conservate." if gizmos.focus.locked else "Gruppo sbloccato."

func _toggle_surface() -> void:
	var node := _village()
	if node==null: _error("Seleziona un villaggio."); return
	var undo := get_undo_redo(); undo.create_action("Suolo automatico",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,"auto_surface",not node.auto_surface); undo.add_undo_property(node,"auto_surface",node.auto_surface)
	undo.add_do_method(node,"refresh_surface"); undo.commit_action()
	status.text="Suolo automatico attivo. Genera / aggiorna riallinea erba, corti e strade." if node.auto_surface else "Suolo automatico disattivato."
func _toggle_zones() -> void:
	var node := _village()
	if node: node.show_zones=not node.show_zones; update_overlays()
