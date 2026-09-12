extends RefCounted
func run(plugin: EditorPlugin) -> void:
	for i in 30: await plugin.get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	var camera := Camera3D.new(); scene.add_child(camera); camera.position=Vector3(25,50,45); camera.look_at(Vector3.ZERO); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=75
	plugin._create()
	var village=plugin._village()
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(scene))
	for kind in 3:
		plugin._draw(kind)
		var points: Array=[Vector3(-30,0,-24),Vector3(30,0,-24),Vector3(30,0,24),Vector3(-30,0,24)] if kind!=1 else [Vector3(-25,0,0),Vector3(25,0,0)]
		for p in points:
			var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=camera.unproject_position(p)
			assert(plugin._forward_3d_gui_input(camera,event)==EditorPlugin.AFTER_GUI_INPUT_STOP)
		var enter := InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; plugin._forward_3d_gui_input(camera,enter)
		assert(village.guides(kind).size()==1)
		history.undo(); assert(village.guides(kind).is_empty()); history.redo(); assert(village.guides(kind).size()==1)
	print("VILLAGE_EDITOR_DRAW_UNDO_OK")
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(village.guides(1)[0]); plugin._selection()
	assert(plugin.tabs.current_tab==1 and plugin.gizmos.focus==village.guides(1)[0])
	var road=village.guides(1)[0]; var points: PackedVector2Array=road.points.duplicate()
	plugin._add_point(); assert(road.points.size()==3); history.undo(); assert(road.points==points); history.redo()
	plugin.tabs.current_tab=2; assert(plugin.gizmos.focus==null,"Inactive context still shows point handles")
	plugin._generate(); assert(not village.failed,village.report); assert(village.lots().size()>0)
	var count: int=village.lots().size(); var first=village.lots()[0]
	history.undo(); assert(village.lots().is_empty()); history.redo(); assert(village.lots().size()==count and village.lots()[0]==first)
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(first); plugin._lock(); assert(first.locked); history.undo(); assert(not first.locked)
	print("VILLAGE_EDITOR_CONTEXT_POINTS_GENERATE_LOCK_UNDO_OK")
	var parent: Node=village.get_parent()
	var undo := plugin.get_undo_redo(); undo.create_action("Test elimina villaggio",UndoRedo.MERGE_DISABLE,scene)
	undo.add_do_method(parent,"remove_child",village); undo.add_undo_method(parent,"add_child",village); undo.commit_action()
	plugin.selected=village
	assert(is_instance_valid(village) and not village.is_inside_tree())
	assert(plugin._village()==null,"Deleted undo-retained village is still active")
	plugin._draw(0)
	assert(plugin.mode==-1 and "Crea o seleziona" in plugin.dialog.dialog_text)
	plugin.dialog.hide()
	history.undo()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(village); plugin._selection()
	assert(plugin._village()==village,"Undo did not restore usable village")
	plugin._create(); var fresh=plugin._village()
	plugin._draw(0); assert(plugin.mode==0 and plugin.draft.get_parent()==fresh)
	plugin._cancel(); plugin._draw(0)
	assert(plugin.mode==0,"Cancelled perimeter still blocks drawing in same frame")
	plugin._cancel()
	print("VILLAGE_DELETE_UNDO_RECREATE_CANCEL_CONTEXT_OK")
	EditorInterface.get_selection().clear(); EditorInterface.edit_node(scene)
	if DisplayServer.get_name()!="headless":
		EditorInterface.get_selection().add_node(road); plugin._selection()
		var container=plugin.panel.get_parent()
		if container is TabContainer: container.current_tab=plugin.panel.get_index()
		for i in 20: await plugin.get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/village_builder"))
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://captures/village_builder/editor.png")
	for i in 2: await plugin.get_tree().process_frame
	plugin.get_tree().quit()
