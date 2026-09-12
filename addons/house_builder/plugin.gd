@tool
extends EditorPlugin
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
var dragging := false
var start := Vector3.ZERO
var end := Vector3.ZERO
var ghost: MeshInstance3D
var target: Node3D
var opening_index := -1
var restore_openings: Array[Dictionary]=[]
var last_root: Node
var _test_runner: RefCounted

func _enter_tree() -> void:
	add_custom_type("HearthHouse","Node3D",House,EditorInterface.get_base_control().get_theme_icon("CSGBox3D","EditorIcons"))
	gizmos=Gizmo.new()
	gizmos.undo=get_undo_redo()
	add_node_3d_gizmo_plugin(gizmos)
	plan_gizmos=preload("res://addons/house_builder/plan_gizmo.gd").new()
	plan_gizmos.undo=get_undo_redo(); add_node_3d_gizmo_plugin(plan_gizmos)
	dock=VBoxContainer.new()
	scroll=ScrollContainer.new()
	scroll.name="Hearth Case"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	dock.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dock.custom_minimum_size.x=230
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
	for label in ["Interni: crea / mostra", "Vista esterna", "Aggiungi piano", "Piano successivo", "Aggiungi stanza", "Aggiungi muro", "Aggiungi scala", "Aggiungi dettaglio", "Genera stanze (piano attivo)", "Rigenera muri dalle stanze", "Blocca / sblocca elemento", "Arreda piano", "Arreda stanza selezionata", "Rimuovi arredo generato"]:
		var action := Button.new(); action.text=label; action.pressed.connect(_plan_action.bind(label)); dock.add_child(action)
	var play := Button.new()
	play.text="▶ Play casa selezionata"
	play.pressed.connect(_play_selected)
	dock.add_child(play)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL,scroll)
	set_input_event_forwarding_always_enabled()
	scene_changed.connect(_scene_changed)
	set_process(true)
	if "--house-editor-test" in OS.get_cmdline_user_args():
		_test_runner=load("res://tools/check_house_editor.gd").new()
		_test_runner.call_deferred("run",self)
func _exit_tree() -> void:
	_cancel()
	remove_node_3d_gizmo_plugin(gizmos)
	remove_node_3d_gizmo_plugin(plan_gizmos)
	remove_custom_type("HearthHouse")
	remove_control_from_docks(scroll)
	scroll.queue_free()
func _scene_changed(_root: Node) -> void: _cancel()
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
	var root := EditorInterface.get_edited_scene_root()
	if root!=last_root:
		_cancel(); last_root=root
func _handles(object: Object) -> bool: return object is House or object is Plan or object is Element or mode!=0

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
func _plan_action(label: String) -> void:
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
	if selected==null: status.text="Seleziona una casa o uno dei suoi elementi."; return
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
	if label in ["Genera stanze (piano attivo)","Rigenera muri dalle stanze","Arreda piano","Arreda stanza selezionata","Rimuovi arredo generato"]:
		var index: int=clampi(plan.active_floor,0,plan.levels().size()-1)
		plan.observe_deletions()
		var before: Array=plan.level_records(index); var after: Array=[]
		if label=="Genera stanze (piano attivo)": after=plan.propose_rooms(index)
		elif label=="Rigenera muri dalle stanze": after=plan.propose_walls(index)
		else:
			var scope := ""
			if label=="Arreda stanza selezionata":
				for e in EditorInterface.get_selection().get_selected_nodes():
					if e is Element and e.kind==0 and e.get_parent()==level: scope=e.stable_id
				if scope=="": status.text="Seleziona una stanza del piano attivo."; return
			after=plan.propose_furniture(index,scope,label=="Rimuovi arredo generato")
		var undo := get_undo_redo(); undo.create_action(label,UndoRedo.MERGE_DISABLE,plan)
		undo.add_do_method(plan,"apply_records",index,after); undo.add_undo_method(plan,"apply_records",index,before); undo.commit_action()
		status.text=plan.generation_report
		return
	var element := Element.new()
	element.kind={"Aggiungi stanza":0,"Aggiungi muro":1,"Aggiungi scala":2,"Aggiungi dettaglio":3}.get(label,0)
	element.name=["Stanza","Muro","Scala","Dettaglio"][element.kind]
	element.stable_id="manual_%s"%str(Time.get_ticks_usec())
	element.dimensions=[Vector3(3,plan.floor_height,3),Vector3(3,plan.floor_height,0.18),Vector3(1.2,plan.floor_height,4.2),Vector3(1,0.8,0.7)][element.kind]
	_add_authored(level,element,label)
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
	_cancel(); mode=value
	# The terrain brush and house placement must not consume the same stroke.
	if mode!=0:
		for other in get_parent().get_children():
			if other!=self and other.get_script()!=null and other.get_script().resource_path=="res://addons/world_editor/plugin.gd":
				if is_instance_valid(other.mode): other.mode.select(0)
	status.text=["Seleziona una casa per modificarla.","Trascina un rettangolo sul terreno.","Clicca per appoggiare una finestra.","Clicca per appoggiare una porta.","Trascina una finestra o una porta.","Clicca l'apertura da rimuovere."][mode]
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
		else: result.append_array(_houses(child))
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
