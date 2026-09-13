@tool
extends EditorPlugin
const ExteriorStair=preload("res://addons/house_builder/exterior_stair.gd")
const Balcony=preload("res://addons/house_builder/balcony.gd")
var balcony_gizmos: EditorNode3DGizmoPlugin
var stair_gizmos: EditorNode3DGizmoPlugin
var balcony_info: Label
var floor_choice: OptionButton
var door_choice: OptionButton
var _binding_key := ""
var placing_terrace := false
const Volume=preload("res://addons/house_builder/volume.gd")
var volume_info: Label
const House=preload("res://addons/house_builder/house.gd")
const Gizmo=preload("res://addons/house_builder/gizmo.gd")
const Plan=preload("res://addons/house_builder/plan.gd")
const Element=preload("res://addons/house_builder/plan_element.gd")
var plan_gizmos: EditorNode3DGizmoPlugin
var gizmos: EditorNode3DGizmoPlugin
var dock: VBoxContainer
var scroll: ScrollContainer
var mode := 0
var buttons: Array[Button]=[]
var status: Label
var error_dialog: AcceptDialog
var dragging := false
var start := Vector3.ZERO
var end := Vector3.ZERO
var ghost: MeshInstance3D
var target: Node3D
var opening_index := -1
var restore_openings: Array[Dictionary]=[]
var last_root: Node
var _test_runner: RefCounted
var tabs: TabContainer
var opening_choice: OptionButton
var context_label: Label
var architecture_choice: OptionButton
var architecture_info: Label
var _architecture_ui_key := ""
var architecture_profiles: Array=[preload("res://addons/house_builder/profiles/compact_timber.tres"),preload("res://addons/house_builder/profiles/nordic_longhouse.tres")]

func _enter_tree() -> void:
	error_dialog=AcceptDialog.new()
	error_dialog.title="House Builder · operazione non eseguita"
	error_dialog.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	error_dialog.get_label().custom_minimum_size.x=480
	error_dialog.ok_button_text="Ho capito"
	EditorInterface.get_base_control().add_child(error_dialog)
	add_custom_type("HearthHouse","Node3D",House,EditorInterface.get_base_control().get_theme_icon("CSGBox3D","EditorIcons"))
	gizmos=Gizmo.new()
	gizmos.undo=get_undo_redo()
	add_node_3d_gizmo_plugin(gizmos)
	balcony_gizmos=preload("res://addons/house_builder/balcony_gizmo.gd").new()
	balcony_gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(balcony_gizmos)
	stair_gizmos=preload("res://addons/house_builder/exterior_stair_gizmo.gd").new(); stair_gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(stair_gizmos)
	plan_gizmos=preload("res://addons/house_builder/plan_gizmo.gd").new()
	plan_gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(plan_gizmos)
	dock=VBoxContainer.new()
	scroll=ScrollContainer.new()
	scroll.name="Hearth Case"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	dock.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dock.custom_minimum_size.x=300
	scroll.add_child(dock)
	var title := Label.new()
	title.text="Case · tetto a due falde"
	dock.add_child(title)
	var group := ButtonGroup.new()
	for text in ["Seleziona / gizmo","Disegna casa","Posiziona finestra","Posiziona porta","Sposta apertura","Rimuovi apertura"]:
		var b := Button.new()
		b.text=text; b.toggle_mode=true; b.button_group=group
		var index := buttons.size()
		b.pressed.connect(_set_mode.bind(index))
		buttons.append(b); dock.add_child(b)
	buttons[0].button_pressed=true
	for label in ["Aggiungi ala a L", "Rimuovi ala"]:
		var action := Button.new()
		action.text=label
		action.pressed.connect(_toggle_wing.bind(label=="Aggiungi ala a L"))
		dock.add_child(action)
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status)
	_set_mode(0)
	var help := Label.new()
	help.text="Casa: trascina sul terreno.\nAperture: clicca una parete.\nManiglie: dimensioni e tetto.\nRotazione: gizmo Godot (E).\nEsc / tasto destro: annulla.\nCtrl+Z: annulla modifica."
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(help)
	var wing_help := Label.new()
	wing_help.text="Ala: seleziona una casa e premi Aggiungi ala a L. Trascina le due nuove maniglie. Lato e aggancio si regolano nell'Inspector → Ala laterale."
	wing_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(wing_help)
	var opening_help := Label.new()
	opening_help.text="Aperture: maniglia centrale per spostare; laterale per larghezza; superiore per altezza. Le porte restano a terra."
	opening_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(opening_help)
	for label in ["Interni: crea / mostra", "Vista esterna", "Aggiungi piano", "Piano successivo", "Aggiungi stanza", "Integra stanza e genera muri", "Aggiungi muro", "Aggiungi scala", "Aggiungi dettaglio", "Genera stanze (piano attivo)", "Rigenera muri dalle stanze", "Blocca / sblocca elemento", "Arreda piano", "Arreda stanza selezionata", "Rimuovi arredo generato"]:
		var action := Button.new(); action.text=label; action.pressed.connect(_plan_action.bind(label)); dock.add_child(action)
	var play := Button.new()
	play.text="▶ Play casa selezionata"
	play.pressed.connect(_play_selected)
	dock.add_child(play)
	_build_context_tabs()
	_build_component_tab()
	_build_volume_tab()
	architecture_choice=OptionButton.new()
	for profile in architecture_profiles: architecture_choice.add_item(profile.display_name)
	tabs.get_child(0).add_child(architecture_choice)
	architecture_info=Label.new(); architecture_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; tabs.get_child(0).add_child(architecture_info)
	for adopt in [false,true]:
		var action := Button.new(); action.text="Cambia profilo · conserva modifiche" if not adopt else "Usa proporzioni del profilo"
		action.pressed.connect(_apply_architecture_profile.bind(adopt)); tabs.get_child(0).add_child(action)
	architecture_choice.item_selected.connect(func(_index): _architecture_details())
	_architecture_details()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL,scroll)
	set_input_event_forwarding_always_enabled()
	scene_changed.connect(_scene_changed)
	EditorInterface.get_selection().selection_changed.connect(_selection_context)
	set_process(true)
	if "--house-editor-test" in OS.get_cmdline_user_args():
		_test_runner=load("res://tools/check_house_editor.gd").new()
		_test_runner.call_deferred("run",self)
func _exit_tree() -> void:
	EditorInterface.get_selection().selection_changed.disconnect(_selection_context)
	error_dialog.queue_free()
	_cancel()
	remove_node_3d_gizmo_plugin(gizmos)
	remove_node_3d_gizmo_plugin(balcony_gizmos)
	remove_node_3d_gizmo_plugin(stair_gizmos)
	remove_node_3d_gizmo_plugin(plan_gizmos)
	remove_custom_type("HearthHouse")
	remove_control_from_docks(scroll)
	scroll.queue_free()
func _scene_changed(_root: Node) -> void: _cancel()
func _build_context_tabs() -> void:
	context_label=Label.new(); context_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(context_label); dock.move_child(context_label,1)
	tabs=TabContainer.new(); tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dock.add_child(tabs); dock.move_child(tabs,2)
	for title in ["Casa","Aperture","Interni","Arredo"]:
		var page := VBoxContainer.new(); page.name=title; tabs.add_child(page)
	var exterior := ["Seleziona / gizmo","Disegna casa","Aggiungi ala a L","Rimuovi ala","Vista esterna"]
	var openings := ["Posiziona finestra","Posiziona porta","Sposta apertura","Rimuovi apertura"]
	var furniture := ["Aggiungi dettaglio","Arreda piano","Arreda stanza selezionata","Rimuovi arredo generato"]
	for child in dock.get_children():
		if child is Button:
			if child.text.begins_with("▶"): continue
			var index := 0 if child.text in exterior else (1 if child.text in openings else (3 if child.text in furniture else 2))
			child.reparent(tabs.get_child(index))
		elif child is Label and child not in [context_label,status] and child!=dock.get_child(0):
			child.queue_free()
	opening_choice=OptionButton.new(); opening_choice.item_selected.connect(_choose_opening)
	tabs.get_child(1).add_child(opening_choice); tabs.get_child(1).move_child(opening_choice,0)
	var furniture_lock := Button.new(); furniture_lock.text="Blocca / sblocca mobile"
	furniture_lock.pressed.connect(_plan_action.bind("Blocca / sblocca elemento")); tabs.get_child(3).add_child(furniture_lock)
	tabs.tab_changed.connect(_context_changed)
	_selection_context()
func _choose_opening(index: int) -> void:
	gizmos.active_opening=index; _refresh_context_gizmos()
func _selection_context() -> void:
	if tabs==null: return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var node: Node=selected[0] if not selected.is_empty() else null
	context_label.text="Selezione: "+str(node.name) if node else "Seleziona una casa o disegnane una."
	if node is Volume: tabs.current_tab=5
	elif node is Balcony or node is ExteriorStair: tabs.current_tab=4
	elif node is Element: tabs.current_tab=3 if node.kind==3 else 2
	elif node is Plan: tabs.current_tab=2
	elif node is House and tabs.current_tab>1: tabs.current_tab=0
	if node is House or node is Plan or node is Element or node is Balcony or node is ExteriorStair: _show_context_dock.call_deferred()
	opening_choice.clear()
	var house := _selected_house()
	if house:
		for i in house.openings.size(): opening_choice.add_item(("Porta" if house.resolved_opening(house.openings[i]).door else "Finestra")+" %d"%(i+1))
		if opening_choice.item_count>0: opening_choice.select(clampi(gizmos.active_opening,0,opening_choice.item_count-1)); gizmos.active_opening=opening_choice.selected
	_refresh_context_gizmos()
	_architecture_details()
func _show_context_dock() -> void:
	var ancestor: Node=scroll.get_parent()
	while ancestor!=null:
		if ancestor is EditorDock: ancestor.make_visible(); return
		ancestor=ancestor.get_parent()
func _context_changed(_index: int) -> void:
	_set_mode(0)
	buttons[0].button_pressed=true
	_refresh_context_gizmos()
func _refresh_context_gizmos() -> void:
	var house := _selected_house()
	gizmos.focus=house; gizmos.context=0 if house is Volume and tabs.current_tab==5 else mini(tabs.current_tab,2)
	balcony_gizmos.focus=null; stair_gizmos.focus=null
	for selected in EditorInterface.get_selection().get_selected_nodes():
		if selected is ExteriorStair and tabs.current_tab==4: stair_gizmos.focus=selected; selected.update_gizmos(); continue
		if selected is Balcony and tabs.current_tab==4: balcony_gizmos.focus=selected; selected.update_gizmos()
	plan_gizmos.focus=null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Element and ((tabs.current_tab==3 and node.kind==3) or (tabs.current_tab==2 and node.kind!=3)): plan_gizmos.focus=node
	var root := EditorInterface.get_edited_scene_root()
	if root:
		for h in _houses(root):
			h.update_gizmos()
			for component in h.attached_components():
				component.update_gizmos()
				if component.stair_component(): component.stair_component().update_gizmos()
			var plan=h.get_node_or_null("InteriorPlan")
			if plan:
				for e in plan.elements(): e.update_gizmos()
func _toggle_wing(enabled: bool) -> void:
	for selected in EditorInterface.get_selection().get_selected_nodes():
		if not selected is House: continue
		_set_mode(0); buttons[0].button_pressed=true
		var undo := get_undo_redo()
		undo.create_action("Aggiungi ala a L" if enabled else "Rimuovi ala",UndoRedo.MERGE_DISABLE,selected)
		undo.add_do_property(selected,"wing_enabled",enabled)
		undo.add_undo_property(selected,"wing_enabled",selected.wing_enabled)
		undo.commit_action()
		EditorInterface.edit_node(selected)
		return
	status.text="Seleziona prima una casa generata."
func _apply_changes() -> void:
	_cancel()
	var root := EditorInterface.get_edited_scene_root()
	if root!=null:
		for house in _houses(root):
			if house._pending: house.rebuild()
func _process(_delta: float) -> void:
	if volume_info:
		var selected_volume := _selected_house()
		volume_info.text=("VOLUME NON RACCORDATO: "+selected_volume.volume_error() if not selected_volume.volume_error().is_empty() else "Raccordo: "+["passaggio aperto","parete con porta"][selected_volume.junction_mode]+". Dimensioni e posizione porta: Inspector, Raccordo interno. Sgancia per usare la trasformazione libera.") if selected_volume is Volume else "Seleziona una casa e aggiungi un corpo basso. Ogni volume conserva tetto e aperture propri."
	_refresh_binding_choices()
	if balcony_info:
		var component := _selected_balcony()
		balcony_info.text=("ERRORE: "+component.validation_error() if not component.validation_error().is_empty() else "Balcone a %.2f m. %s"%[component.effective_elevation(),"Segue la porta manuale selezionata." if not component.door_id.is_empty() else ("Quota collegata al piano." if not component.floor_id.is_empty() else "Quota manuale.")]) if component else "Posiziona un balcone sulla facciata: il clic indica la quota del pavimento. Servono almeno 2,12 m di muro sopra. Seleziona il balcone per modificarlo."
	var selected_house := _selected_house()
	var key := str(selected_house.dimensions(),selected_house.architecture_profile,selected_house.profile_baseline) if selected_house else ""
	if key!=_architecture_ui_key: _architecture_ui_key=key; _architecture_details()
	var root := EditorInterface.get_edited_scene_root()
	if root!=last_root:
		_cancel(); last_root=root
func _handles(object: Object) -> bool: return object is ExteriorStair or object is Balcony or object is House or object is Plan or object is Element or mode!=0

func _selected_house() -> Node3D:
	for selected in EditorInterface.get_selection().get_selected_nodes():
		var node: Node=selected
		while node!=null:
			if node is House: return node
			node=node.get_parent()
	return null
func _owned(node: Node,root: Node) -> void:
	if node!=root: node.owner=root
	for child in node.get_children(): _owned(child,root)
func _attach(parent: Node,node: Node,root: Node) -> void:
	parent.add_child(node,true); _owned(node,root)
	if parent is Plan: parent._pending=true
	elif parent.get_parent() is Plan: parent.get_parent()._pending=true
func _add_authored(parent: Node,node: Node,label: String) -> void:
	var undo := get_undo_redo(); undo.create_action(label,UndoRedo.MERGE_DISABLE,parent)
	undo.add_do_method(self,"_attach",parent,node,EditorInterface.get_edited_scene_root())
	undo.add_undo_method(parent,"remove_child",node); undo.add_do_reference(node); undo.commit_action()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(node); EditorInterface.edit_node(node)
func _show_plan_error(action: String,message: String) -> void:
	status.text="OPERAZIONE NON ESEGUITA\n"+message
	status.add_theme_color_override("font_color",Color(1.0,0.38,0.28))
	error_dialog.dialog_text=action+"\n\n"+message+"\n\nLa scena non è stata modificata."
	error_dialog.popup_centered(Vector2i(540,230))
	push_warning("House Builder — "+action+": "+message)
func _plan_action(label: String) -> void:
	status.remove_theme_color_override("font_color")
	if label=="Blocca / sblocca elemento":
		for e in EditorInterface.get_selection().get_selected_nodes():
			if not e is Element: continue
			var undo := get_undo_redo(); undo.create_action("Protezione elemento",UndoRedo.MERGE_DISABLE,e)
			undo.add_do_property(e,"locked",not e.locked); undo.add_undo_property(e,"locked",e.locked)
			if e.locked:
				undo.add_do_property(e,"baseline",e.record()); undo.add_undo_property(e,"baseline",e.baseline.duplicate(true))
			undo.commit_action()
		return
	var selected := _selected_house()
	if selected==null: _show_plan_error(label,"Seleziona una casa o uno dei suoi elementi."); return
	var plan=selected.get_node_or_null("InteriorPlan")
	if plan==null:
		plan=Plan.new(); plan.name="InteriorPlan"
		var floor_node := Node3D.new(); floor_node.name="Piano_1"; plan.add_child(floor_node)
		_add_authored(selected,plan,"Crea interni modificabili")
	if label=="Vista esterna": plan.preview_inside=false; return
	plan.preview_inside=true
	if label=="Interni: crea / mostra": EditorInterface.edit_node(plan); return
	if label=="Piano successivo": plan.active_floor=(plan.active_floor+1)%maxi(1,plan.levels().size()); return
	if label=="Aggiungi piano":
		if plan.levels().size()>=3: status.text="Massimo tre piani in questa versione."; return
		var floor_node := Node3D.new(); floor_node.name="Piano_%d"%(plan.levels().size()+1)
		_add_authored(plan,floor_node,"Aggiungi piano"); plan.active_floor=plan.levels().size()-1; return
	var level: Node3D=plan.levels()[clampi(plan.active_floor,0,plan.levels().size()-1)]
	for e in EditorInterface.get_selection().get_selected_nodes():
		var ancestor: Node=e
		while ancestor is Node3D and ancestor!=plan and ancestor not in plan.levels(): ancestor=ancestor.get_parent()
		if ancestor is Node3D and ancestor in plan.levels():
			level=ancestor; plan.active_floor=plan.levels().find(level); break
	if label in ["Genera stanze (piano attivo)","Rigenera muri dalle stanze","Integra stanza e genera muri","Arreda piano","Arreda stanza selezionata","Rimuovi arredo generato"]:
		var index: int=clampi(plan.active_floor,0,plan.levels().size()-1)
		plan.observe_deletions()
		var before: Array=plan.level_records(index); var after: Array=[]
		if label=="Genera stanze (piano attivo)": after=plan.propose_rooms(index)
		elif label=="Rigenera muri dalle stanze": after=plan.propose_walls(index)
		elif label=="Integra stanza e genera muri":
			var room_id := ""
			for e in EditorInterface.get_selection().get_selected_nodes():
				if e is Element and e.kind==0 and e.get_parent()==level: room_id=e.stable_id
			after=plan.propose_insert_room(index,room_id)
		else:
			var scope := ""
			if label=="Arreda stanza selezionata":
				for e in EditorInterface.get_selection().get_selected_nodes():
					if e is Element and e.kind==0 and e.get_parent()==level: scope=e.stable_id
				if scope=="": _show_plan_error(label,"Seleziona una stanza del piano attivo."); return
			after=plan.propose_furniture(index,scope,label=="Rimuovi arredo generato")
		if plan.generation_failed:
			_show_plan_error(label,plan.generation_report); return
		if after==before:
			status.text="Nessuna modifica necessaria. "+plan.generation_report; return
		var undo := get_undo_redo(); undo.create_action(label,UndoRedo.MERGE_DISABLE,plan)
		undo.add_do_method(plan,"apply_records",index,after); undo.add_undo_method(plan,"apply_records",index,before); undo.commit_action()
		status.text=plan.generation_report
		return
	var element := Element.new()
	element.kind={"Aggiungi stanza":0,"Aggiungi muro":1,"Aggiungi scala":2,"Aggiungi dettaglio":3}.get(label,0)
	element.name=["Stanza","Muro","Scala","Dettaglio"][element.kind]
	element.stable_id="manual_%s"%str(Time.get_ticks_usec())
	element.dimensions=[Vector3(3,plan.floor_height,3),Vector3(3,plan.floor_height,0.18),Vector3(1.2,plan.floor_height,4.2),Vector3(1,0.8,0.7)][element.kind]
	var parent: Node=level
	if element.kind==3:
		for e in EditorInterface.get_selection().get_selected_nodes():
			var candidate: Node=e
			if candidate is Element and candidate.kind==3: candidate=candidate.get_parent()
			if candidate is Element and candidate.kind==0:
				parent=candidate; element.room_ids=PackedStringArray([candidate.stable_id]); break
	_add_authored(parent,element,label)
	if element.kind==0: status.text="Posiziona e dimensiona la stanza, poi premi Integra stanza e genera muri. Room Type sceglie la funzione; Display Name il nome."
func _play_selected() -> void:
	var selected := _selected_house()
	if selected==null: status.text="Seleziona la casa da provare."; return
	var packed := _snapshot(selected)
	var error := ResourceSaver.save(packed,"user://house_builder_playtest.tscn") if packed else ERR_CANT_CREATE
	if error!=OK: status.text="Impossibile preparare la prova: %d"%error; return
	EditorInterface.play_custom_scene("res://scenes/dev/house_interior_playable.tscn")
func _snapshot(selected: Node3D) -> PackedScene:
	selected.rebuild()
	var clone: Node3D=selected.duplicate()
	clone.transform=Transform3D.IDENTITY; clone.owner=null; _owned(clone,clone)
	var packed := PackedScene.new(); var error := packed.pack(clone)
	clone.free()
	return packed if error==OK else null
func _set_mode(value: int) -> void:
	_cancel(); mode=value; placing_terrace=false
	# The terrain brush and house placement must not consume the same stroke.
	if mode!=0:
		for other in get_parent().get_children():
			if other!=self and other.get_script()!=null and other.get_script().resource_path=="res://addons/world_editor/plugin.gd":
				if is_instance_valid(other.mode): other.mode.select(0)
	status.text=["Seleziona una casa per modificarla.","Trascina un rettangolo sul terreno.","Clicca per appoggiare una finestra.","Clicca per appoggiare una porta.","Trascina una finestra o una porta.","Clicca l'apertura da rimuovere.","Clicca la facciata alla quota del pavimento del balcone."][mode]
func _cancel() -> void:
	if dragging and is_instance_valid(target) and opening_index>=0: target.openings=restore_openings
	dragging=false; target=null; opening_index=-1
	if is_instance_valid(ghost): ghost.queue_free()
	ghost=null
func _world_parent() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root==null: return null
	return root.get_node("Pixel/View") if root.has_node("Pixel/View") else root
func _ground(camera: Camera3D,position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*3000.0)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.y>0.6: return hit.position
	return Plane(Vector3.UP,start.y if dragging else 0.0).intersects_ray(origin,direction)
func _houses(root: Node) -> Array[Node3D]:
	var result: Array[Node3D]=[]
	for child in root.get_children():
		if child is House: result.append(child)
		result.append_array(_houses(child))
	return result
func _wall(camera: Camera3D,position: Vector2) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root==null: return {}
	var best := {}
	for house in _houses(root):
		var hit: Dictionary=house.hit_wall(camera.project_ray_origin(position),camera.project_ray_normal(position))
		if not hit.is_empty() and (best.is_empty() or hit.distance<best.distance): best=hit
	return best
func _nearest_opening(house: Node3D,hit: Dictionary) -> int:
	var best := -1
	var distance := INF
	for i in house.openings.size():
		var o: Dictionary=house.resolved_opening(house.openings[i])
		if o.wall!=hit.wall: continue
		var dx: float=absf(o.along-hit.u*house.wall_length(o.wall)*0.5)
		var dy: float=absf(o.y-hit.y)
		if dx<o.width*0.5+0.15 and dy<o.height*0.5+0.15 and dx+dy<distance:
			best=i; distance=dx+dy
	return best
func _record(hit: Dictionary,kind: String) -> Dictionary:
	return {"kind":kind,"wall":hit.wall,"u":hit.u,"y":snappedf(hit.y,0.1)}
func _commit_openings(house: Node3D,before: Array[Dictionary],after: Array[Dictionary],name_action: String) -> void:
	var undo := get_undo_redo()
	undo.create_action(name_action,UndoRedo.MERGE_DISABLE,house)
	undo.add_do_property(house,"openings",after)
	undo.add_undo_property(house,"openings",before)
	undo.commit_action()
func _create_house() -> void:
	var parent := _world_parent()
	if parent==null: return
	var size := (end-start).abs()
	if size.x<0.5 or size.z<0.5: return
	var node := House.new()
	node.name="Casa"
	node.width=snappedf(size.x,0.1); node.depth=snappedf(size.z,0.1)
	node.position=(parent as Node3D).to_local(Vector3((start.x+end.x)*0.5,start.y,(start.z+end.z)*0.5)) if parent is Node3D else Vector3((start.x+end.x)*0.5,start.y,(start.z+end.z)*0.5)
	node.openings=[{"kind":"door","wall":0,"u":-0.35},{"kind":"window","wall":0,"u":0.45,"y":1.55}]
	var undo := get_undo_redo()
	undo.create_action("Disegna casa",UndoRedo.MERGE_DISABLE,parent)
	undo.add_do_method(parent,"add_child",node,true)
	undo.add_do_property(node,"owner",EditorInterface.get_edited_scene_root())
	undo.add_do_reference(node)
	undo.add_undo_method(parent,"remove_child",node)
	undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)
func _preview() -> void:
	if not is_instance_valid(ghost):
		ghost=MeshInstance3D.new()
		ghost.mesh=BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color=Color(1.0,0.65,0.15,0.28)
		ghost.material_override=material
		ghost.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world_parent().add_child(ghost)
	ghost.mesh.size=Vector3(maxf(absf(end.x-start.x),0.1),2.6,maxf(absf(end.z-start.z),0.1))
	ghost.global_position=Vector3((start.x+end.x)*0.5,start.y+1.3,(start.z+end.z)*0.5)
func _forward_3d_gui_input(camera: Camera3D,event: InputEvent) -> int:
	if mode==0: return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		_cancel(); buttons[0].button_pressed=true; _set_mode(0); return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		_cancel(); return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		if mode==6:
			_preview_balcony(_wall(camera,event.position)); return AFTER_GUI_INPUT_STOP
		if dragging and mode==1:
			var p=_ground(camera,event.position)
			if p!=null: end=p; _preview()
		elif dragging and mode==4 and is_instance_valid(target):
			var hit: Dictionary=target.hit_wall(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if not hit.is_empty():
				var records: Array[Dictionary]=target.openings.duplicate(true)
				records[opening_index].merge(_record(hit,records[opening_index].get("kind","window")),true)
				if target.opening_fits(records[opening_index],opening_index): target.openings=records
		return AFTER_GUI_INPUT_STOP if dragging else AFTER_GUI_INPUT_PASS
	if not (event is InputEventMouseButton) or event.button_index!=MOUSE_BUTTON_LEFT: return AFTER_GUI_INPUT_PASS
	if not event.pressed:
		if dragging and mode==1: _create_house()
		elif dragging and mode==4 and is_instance_valid(target):
			_commit_openings(target,restore_openings,target.openings.duplicate(true),"Sposta apertura")
		opening_index=-1; _cancel()
		return AFTER_GUI_INPUT_STOP
	if mode==1:
		var p=_ground(camera,event.position)
		if p!=null and _world_parent()!=null: start=p; end=p; dragging=true; _preview()
	else:
		var hit := _wall(camera,event.position)
		if hit.is_empty(): return AFTER_GUI_INPUT_STOP
		var house: Node3D=hit.house
		var records: Array[Dictionary]=house.openings.duplicate(true)
		if mode==6:
			_place_balcony(hit); return AFTER_GUI_INPUT_STOP
		if mode in [2,3]:
			if not house.opening_fits(_record(hit,"window" if mode==2 else "door")):
				status.text="Aperture troppo vicine: scegli un punto libero."
				return AFTER_GUI_INPUT_STOP
			var changed: Array[Dictionary]=records.duplicate(true)
			changed.append(_record(hit,"window" if mode==2 else "door"))
			_commit_openings(house,records,changed,"Aggiungi apertura")
		elif mode==4:
			opening_index=_nearest_opening(house,hit)
			if opening_index>=0: target=house; restore_openings=records; dragging=true
		elif mode==5:
			var index := _nearest_opening(house,hit)
			if index>=0:
				var changed: Array[Dictionary]=records.duplicate(true)
				changed.remove_at(index)
				_commit_openings(house,records,changed,"Rimuovi apertura")
	return AFTER_GUI_INPUT_STOP

func _architecture_details() -> void:
	if architecture_info==null: return
	var house := _selected_house()
	if house==null: architecture_info.text="Seleziona una casa. I profili cambiano le proporzioni, non i materiali."; return
	var inherited := PackedStringArray(); var manual := PackedStringArray()
	for key in ["width","depth","wall_height","roof_height"]:
		var label: String={"width":"larghezza","depth":"lunghezza","wall_height":"pareti","roof_height":"tetto"}[key]
		if house.inherited_dimension(key): inherited.append(label)
		else: manual.append(label)
	architecture_info.text="Attivo: %s
Ereditato: %s
Manuale: %s
Usa proporzioni sostituisce queste quattro dimensioni. Aperture e dettagli restano conservati."%[house.architecture_profile.display_name if house.architecture_profile else "Legacy / manuale",", ".join(inherited),", ".join(manual)]
func _apply_architecture_profile(adopt: bool) -> void:
	var house := _selected_house()
	if house==null: status.text="Seleziona una casa."; return
	var before: Dictionary=house.architecture_state(); var after: Dictionary=house.architecture_proposal(architecture_profiles[architecture_choice.selected],adopt)
	var undo := get_undo_redo(); undo.create_action("Profilo architettonico",UndoRedo.MERGE_DISABLE,house)
	undo.add_do_method(house,"apply_architecture",after); undo.add_undo_method(house,"apply_architecture",before)
	undo.add_do_method(self,"_architecture_details"); undo.add_undo_method(self,"_architecture_details"); undo.commit_action()
	status.text="Profilo aggiornato. Materiali, aperture e dettagli conservati."

func _build_component_tab() -> void:
	var page := VBoxContainer.new(); page.name="Componenti"; tabs.add_child(page)
	var add := Button.new(); add.text="Posiziona balcone + porta"; add.pressed.connect(_set_mode.bind(6)); page.add_child(add)
	var terrace := Button.new(); terrace.text="Posiziona terrazza + scala"; terrace.pressed.connect(_start_terrace); page.add_child(terrace)
	var convert := Button.new(); convert.text="Aggiungi pilastri e scala al selezionato"; convert.pressed.connect(_terrace_selected.bind(true)); page.add_child(convert)
	for side in 3:
		var side_button := Button.new(); side_button.text="Scala indipendente · "+["frontale","destra","sinistra"][side]
		side_button.pressed.connect(_attach_stair.bind(side)); page.add_child(side_button)
	var detach := Button.new(); detach.text="Elimina scala indipendente"; detach.pressed.connect(_delete_stair); page.add_child(detach)
	var stairs_off := Button.new(); stairs_off.text="Rimuovi scala esterna"; stairs_off.pressed.connect(_terrace_selected.bind(false)); page.add_child(stairs_off)
	var remove := Button.new(); remove.text="Rimuovi componente selezionato"; remove.pressed.connect(_remove_balcony); page.add_child(remove)
	floor_choice=OptionButton.new(); page.add_child(floor_choice)
	var floor_button := Button.new(); floor_button.text="Applica collegamento al piano"; floor_button.pressed.connect(_bind_balcony_floor); page.add_child(floor_button)
	door_choice=OptionButton.new(); page.add_child(door_choice)
	var door_button := Button.new(); door_button.text="Applica accesso"; door_button.pressed.connect(_bind_balcony_door); page.add_child(door_button)
	balcony_info=Label.new(); balcony_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; page.add_child(balcony_info)
func _selected_balcony() -> Node3D:
	for selected in EditorInterface.get_selection().get_selected_nodes():
		var node: Node=selected
		while node:
			if node is Balcony: return node
			node=node.get_parent()
	return null
func _place_balcony(hit: Dictionary) -> void:
	if hit.wall>=4: _show_plan_error("Balcone","Questo primo componente supporta le quattro facciate del corpo principale."); return
	var h: Node=hit.house
	var container := h.get_node_or_null("Components")
	var fresh := container==null
	if fresh: container=Node3D.new(); container.name="Components"; h.add_child(container)
	var component := Balcony.new(); component.name="Balcone"
	component.host_id=["main/front","main/back","main/right","main/left"][hit.wall]
	component.along=hit.u; component.elevation=snappedf(hit.y,0.1)
	if placing_terrace:
		component.name="Terrazza"; component.support_posts=true; component.projection=2.4
		var stair := ExteriorStair.new(); stair.name="ScalaEsterna"; component.add_child(stair)
	container.add_child(component)
	var error := component.validation_error()
	container.remove_child(component)
	if fresh: h.remove_child(container)
	if not error.is_empty():
		component.free()
		if fresh: container.free()
		_show_plan_error("Balcone",error); return
	var undo := get_undo_redo(); undo.create_action("Aggancia balcone e porta",UndoRedo.MERGE_DISABLE,h)
	if fresh:
		undo.add_do_method(self,"_attach",h,container,EditorInterface.get_edited_scene_root())
		undo.add_undo_method(h,"remove_child",container); undo.add_do_reference(container)
	undo.add_do_method(self,"_attach",container,component,EditorInterface.get_edited_scene_root())
	undo.add_undo_method(container,"remove_child",component); undo.add_do_reference(component)
	undo.add_do_method(h,"request_rebuild"); undo.add_undo_method(h,"request_rebuild"); undo.commit_action()
	_set_mode(0); EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(component); EditorInterface.edit_node(component); _selection_context()
func _remove_balcony() -> void:
	var component := _selected_balcony()
	if component==null: status.text="Seleziona un balcone nell’albero della scena."; return
	var parent := component.get_parent(); var h: Node=component.house()
	var undo := get_undo_redo(); undo.create_action("Rimuovi balcone e porta derivata",UndoRedo.MERGE_DISABLE,h)
	undo.add_do_method(parent,"remove_child",component)
	undo.add_undo_method(self,"_attach",parent,component,EditorInterface.get_edited_scene_root()); undo.add_undo_reference(component)
	undo.add_do_method(h,"request_rebuild"); undo.add_undo_method(h,"request_rebuild"); undo.commit_action()

func _preview_balcony(hit: Dictionary) -> void:
	if hit.is_empty() or hit.wall>=4:
		if is_instance_valid(ghost): ghost.hide()
		return
	if not is_instance_valid(ghost):
		ghost=MeshInstance3D.new(); ghost.mesh=BoxMesh.new()
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_color=Color(0.2,0.8,1,0.45)
		ghost.material_override=material; ghost.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _world_parent().add_child(ghost)
	ghost.show(); ghost.mesh.size=Vector3(3,0.15,2.4 if placing_terrace else 1.5)
	var h: Node3D=hit.house
	var tangent: Vector3=(h.wall_point(hit.wall,1,0)-h.wall_point(hit.wall,0,0)).normalized()
	ghost.global_transform=h.global_transform*Transform3D(Basis(tangent,Vector3.UP,h.wall_normal(hit.wall)),h.wall_point(hit.wall,hit.u*h.wall_length(hit.wall)*0.5,snappedf(hit.y,0.1)-0.08,1.2 if placing_terrace else 0.75))
	if placing_terrace:
		var stair_preview: MeshInstance3D=ghost.get_node_or_null("ScalaPreview")
		if stair_preview==null:
			stair_preview=MeshInstance3D.new(); stair_preview.name="ScalaPreview"; stair_preview.mesh=BoxMesh.new(); stair_preview.material_override=ghost.material_override
			stair_preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; ghost.add_child(stair_preview)
		var rise: float=maxf(0.1,snappedf(hit.y,0.1)); var run := rise/tan(deg_to_rad(32.0))+0.45
		stair_preview.mesh.size=Vector3(1.2,0.08,sqrt(run*run+rise*rise))
		stair_preview.position=Vector3(0,-rise*0.5+0.08,1.2+run*0.5); stair_preview.rotation.x=atan2(rise,run)


func _refresh_binding_choices() -> void:
	if floor_choice==null: return
	var b := _selected_balcony()
	if b==null:
		floor_choice.disabled=true; door_choice.disabled=true; _binding_key=""; return
	floor_choice.disabled=false; door_choice.disabled=false
	var h: Node=b.house(); var plan := h.get_node_or_null("InteriorPlan")
	var levels: Array=plan.levels() if plan else []
	var key := str(b.get_instance_id(),b.floor_id,b.door_id,h.openings)
	for level in levels: key+=str(level.name,level.get_meta("floor_id",""))
	if key==_binding_key: return
	_binding_key=key
	floor_choice.clear(); floor_choice.add_item("Quota manuale"); floor_choice.set_item_metadata(0,null)
	for level in levels:
		floor_choice.add_item(str(level.name)); floor_choice.set_item_metadata(floor_choice.item_count-1,level)
		if not b.floor_id.is_empty() and str(level.get_meta("floor_id",""))==b.floor_id: floor_choice.select(floor_choice.item_count-1)
	door_choice.clear(); door_choice.add_item("Porta generata dal balcone"); door_choice.set_item_metadata(0,-1)
	for i in h.openings.size():
		var record: Dictionary=h.openings[i]
		if record.get("kind","window")!="door": continue
		door_choice.add_item("Porta %d · facciata %d"%[i+1,int(record.get("wall",0))+1]); door_choice.set_item_metadata(door_choice.item_count-1,i)
		if not b.door_id.is_empty() and str(record.get("opening_id",""))==b.door_id: door_choice.select(door_choice.item_count-1)
func _binding_state(b: Node3D) -> Dictionary:
	return {"floor_id":b.floor_id,"door_id":b.door_id,"elevation":b.elevation,"along":b.along,"host_id":b.host_id,"create_door":b.create_door,"openings":b.house().openings.duplicate(true)}
func _restore_binding(b: Node3D,state: Dictionary) -> void:
	for key in state:
		if key!="openings": b.set(key,state[key])
	b.house().openings=state.openings; b.house().rebuild(); _binding_key=""
func _commit_binding(b: Node3D,before: Dictionary,after: Dictionary) -> void:
	var undo := get_undo_redo(); undo.create_action("Collega balcone a piano / accesso",UndoRedo.MERGE_DISABLE,b)
	undo.add_do_method(self,"_restore_binding",b,after); undo.add_undo_method(self,"_restore_binding",b,before); undo.commit_action()
func _bind_balcony_floor() -> void:
	var b := _selected_balcony()
	if b==null: return
	var before := _binding_state(b); var after := before.duplicate(true)
	var level: Node=floor_choice.get_selected_metadata()
	after.elevation=b.effective_elevation()
	after.floor_id=""
	if level:
		if not level.has_meta("floor_id"): level.set_meta("floor_id","floor_"+str(Time.get_ticks_usec())+"_"+str(level.get_instance_id()))
		after.floor_id=str(level.get_meta("floor_id"))
	for record in after.openings:
		if not b.door_id.is_empty() and str(record.get("opening_id",""))==b.door_id:
			record.floor_y=b.house().opening_floor_y(record); record.floor_id=after.floor_id
	_commit_binding(b,before,after)
func _bind_balcony_door() -> void:
	var b := _selected_balcony()
	if b==null: return
	var before := _binding_state(b); var after := before.duplicate(true)
	after.along=b.effective_along(); after.elevation=b.effective_elevation()
	after.host_id=["main/front","main/back","main/right","main/left"][b.wall()]
	var index: int=door_choice.get_selected_metadata()
	after.door_id=""; after.create_door=true
	if index>=0:
		var record: Dictionary=after.openings[index]
		if int(record.get("wall",0))>=4: _show_plan_error("Accesso","Le porte sulle ali non sono ancora supportate."); return
		if str(record.get("opening_id","")).is_empty(): record.opening_id="door_"+str(Time.get_ticks_usec())
		after.door_id=record.opening_id
		if not b.floor_id.is_empty(): record.floor_y=b.effective_elevation(); record.floor_id=b.floor_id
	_commit_binding(b,before,after)

func _start_terrace() -> void:
	_set_mode(6); placing_terrace=true
	status.text="Clicca la facciata alla quota della terrazza. Scala frontale fino alla quota terreno (Inspector)."
func _terrace_selected(enabled: bool) -> void:
	var b := _selected_balcony()
	if b==null: status.text="Seleziona un balcone o una terrazza."; return
	var undo := get_undo_redo(); undo.create_action("Configura terrazza e scala",UndoRedo.MERGE_DISABLE,b)
	var stair: Node3D=b.stair_component()
	if stair:
		undo.add_do_property(stair,"enabled",enabled); undo.add_undo_property(stair,"enabled",stair.enabled)
	undo.add_do_property(b,"exterior_stairs",enabled if stair==null else false); undo.add_undo_property(b,"exterior_stairs",b.exterior_stairs)
	if enabled:
		undo.add_do_property(b,"support_posts",true); undo.add_undo_property(b,"support_posts",b.support_posts)
		undo.add_do_property(b,"projection",maxf(b.projection,2.4)); undo.add_undo_property(b,"projection",b.projection)
	undo.commit_action()

func _attach_stair(side: int) -> void:
	var b := _selected_balcony()
	if b==null: status.text="Seleziona una terrazza o la sua scala."; return
	var stair: Node3D=b.stair_component(); var fresh := stair==null
	if fresh:
		stair=ExteriorStair.new(); stair.name="ScalaEsterna"; stair.width=b.stair_width; stair.offset=b.stair_offset; stair.ground_level=b.ground_level
	var undo := get_undo_redo(); undo.create_action("Aggancia scala al bordo",UndoRedo.MERGE_DISABLE,b)
	if fresh:
		undo.add_do_method(self,"_attach",b,stair,EditorInterface.get_edited_scene_root())
		undo.add_do_reference(stair)
	undo.add_do_property(stair,"side",side); undo.add_undo_property(stair,"side",stair.side)
	undo.add_do_property(stair,"enabled",true); undo.add_undo_property(stair,"enabled",stair.enabled)
	undo.add_do_property(b,"exterior_stairs",false); undo.add_undo_property(b,"exterior_stairs",b.exterior_stairs)
	if fresh: undo.add_undo_method(self,"_detach_stair",b,stair)
	undo.commit_action()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(stair); EditorInterface.edit_node(stair); _selection_context()
func _delete_stair() -> void:
	var b := _selected_balcony()
	if b==null or b.stair_component()==null: return
	var stair: Node3D=b.stair_component(); var undo := get_undo_redo()
	undo.create_action("Elimina scala indipendente",UndoRedo.MERGE_DISABLE,b)
	undo.add_do_method(self,"_detach_stair",b,stair); undo.add_undo_method(self,"_attach",b,stair,EditorInterface.get_edited_scene_root()); undo.add_undo_reference(stair)
	undo.commit_action()

func _detach_stair(host: Node3D,stair: Node3D) -> void:
	if stair in EditorInterface.get_selection().get_selected_nodes():
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(host); EditorInterface.edit_node(host)
	stair_gizmos.focus=null
	host.remove_child(stair); _selection_context()

func _build_volume_tab() -> void:
	var page := VBoxContainer.new(); page.name="Volumi"; tabs.add_child(page)
	for side in 4:
		var button := Button.new(); button.text="Aggiungi corpo · "+["davanti","dietro","destra","sinistra"][side]; button.pressed.connect(_add_volume.bind(side)); page.add_child(button)
	for attached in [false,true]:
		var button := Button.new(); button.text="Riaggancia volume" if attached else "Sgancia volume"; button.pressed.connect(_toggle_volume.bind(attached)); page.add_child(button)
	for kind in 2:
		var button := Button.new(); button.text=["Raccordo · passaggio aperto","Raccordo · parete con porta"][kind]; button.pressed.connect(_set_volume_junction.bind(kind)); page.add_child(button)
	var remove := Button.new(); remove.text="Rimuovi volume selezionato"; remove.pressed.connect(_remove_volume); page.add_child(remove)
	volume_info=Label.new(); volume_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; page.add_child(volume_info)
func _add_volume(side: int) -> void:
	var host := _selected_house()
	if host is Volume: host=host.volume_host()
	if host==null: status.text="Seleziona una casa."; return
	var container := host.get_node_or_null("Volumes"); var fresh := container==null
	if fresh: container=Node3D.new(); container.name="Volumes"; host.add_child(container)
	var volume := Volume.new(); volume.name="CorpoAccessorio"; volume.width=3.0; volume.depth=4.0; volume.wall_height=2.6; volume.roof_height=1.2; volume.host_wall=side
	volume.openings=[{"kind":"window","wall":0,"u":0.0,"y":1.4}]
	container.add_child(volume); volume.prepare_attachment(); var error := volume.volume_error()
	container.remove_child(volume)
	if fresh: host.remove_child(container)
	if not error.is_empty():
		volume.free()
		if fresh: container.free()
		_show_plan_error("Corpo accessorio",error); return
	var undo := get_undo_redo(); undo.create_action("Aggiungi corpo accessorio",UndoRedo.MERGE_DISABLE,host)
	if fresh:
		undo.add_do_method(self,"_attach",host,container,EditorInterface.get_edited_scene_root()); undo.add_do_reference(container)
	undo.add_do_method(self,"_attach",container,volume,EditorInterface.get_edited_scene_root()); undo.add_do_reference(volume)
	undo.add_do_method(host,"request_rebuild")
	undo.add_undo_method(self,"_detach_volume",host,container,volume)
	if fresh: undo.add_undo_method(host,"remove_child",container)
	undo.commit_action()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(volume); EditorInterface.edit_node(volume); _selection_context()
func _detach_volume(host: Node3D,container: Node3D,volume: Node3D) -> void:
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(host); EditorInterface.edit_node(host)
	container.remove_child(volume); host.request_rebuild(); _selection_context()
func _toggle_volume(attached: bool) -> void:
	var volume := _selected_house()
	if not volume is Volume: return
	var undo := get_undo_redo(); undo.create_action("Aggancio volume",UndoRedo.MERGE_DISABLE,volume)
	undo.add_do_property(volume,"attached",attached); undo.add_undo_property(volume,"attached",volume.attached)
	undo.add_undo_property(volume,"transform",volume.transform); undo.commit_action()

func _remove_volume() -> void:
	var volume := _selected_house()
	if not volume is Volume: return
	var host: Node3D=volume.volume_host(); var container := volume.get_parent()
	var undo := get_undo_redo(); undo.create_action("Rimuovi corpo accessorio",UndoRedo.MERGE_DISABLE,host)
	undo.add_do_method(self,"_detach_volume",host,container,volume)
	undo.add_undo_method(self,"_attach",container,volume,EditorInterface.get_edited_scene_root()); undo.add_undo_reference(volume)
	undo.add_undo_method(host,"request_rebuild"); undo.commit_action()

func _set_volume_junction(kind: int) -> void:
	var volume := _selected_house()
	if not volume is Volume: return
	var undo := get_undo_redo(); undo.create_action("Cambia raccordo volume",UndoRedo.MERGE_DISABLE,volume)
	undo.add_do_property(volume,"junction_mode",kind); undo.add_undo_property(volume,"junction_mode",volume.junction_mode); undo.commit_action()
