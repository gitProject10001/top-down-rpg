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
		assert(plugin.drawing_actions.visible)
		var points: Array=[Vector3(-30,0,-24),Vector3(30,0,-24),Vector3(30,0,24),Vector3(-30,0,24)] if kind!=1 else [Vector3(-25,0,0),Vector3(25,0,0)]
		for p in points:
			var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=camera.unproject_position(p)
			assert(plugin._forward_3d_gui_input(camera,event)==EditorPlugin.AFTER_GUI_INPUT_STOP)
		if kind==0:
			var motion := InputEventMouseMotion.new(); motion.position=camera.unproject_position(Vector3(-20,0,15)); plugin._forward_3d_gui_input(camera,motion)
			assert(plugin.cursor_visible and plugin.draft.points.size()==4)
			if DisplayServer.get_name()!="headless":
				var saved: PackedVector2Array=plugin.draft.points.duplicate()
				var viewport := EditorInterface.get_editor_viewport_3d(0)
				var native_camera := viewport.get_camera_3d()
				plugin.draft.points=PackedVector2Array()
				for fraction in [Vector2(0.3,0.35),Vector2(0.7,0.35),Vector2(0.7,0.75),Vector2(0.3,0.75)]:
					var click := InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=Vector2(viewport.size)*fraction
					plugin._forward_3d_gui_input(native_camera,click)
				for i in 20: await plugin.get_tree().process_frame
				await RenderingServer.frame_post_draw
				assert(plugin.preview_draw_count>0,"Native viewport did not draw perimeter preview")
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/village_builder"))
				EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://captures/village_builder/drawing.png")
				plugin.draft.points=saved; plugin.drawing_camera=camera
		var enter := InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; plugin._forward_3d_gui_input(camera,enter)
		assert(not plugin.drawing_actions.visible)
		assert(village.guides(kind).size()==1)
		history.undo(); assert(village.guides(kind).is_empty()); history.redo(); assert(village.guides(kind).size()==1)
	print("VILLAGE_EDITOR_DRAW_UNDO_OK")
	plugin.tabs.current_tab=3
	plugin._begin_paint(); assert(plugin.mode==5)
	var down := InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=camera.unproject_position(village.to_global(Vector3.ZERO))
	plugin._forward_3d_gui_input(camera,down)
	var up := InputEventMouseButton.new(); up.button_index=MOUSE_BUTTON_LEFT; up.pressed=false; up.position=down.position
	plugin._forward_3d_gui_input(camera,up)
	var painted: float=village.density_at(Vector2.ZERO); assert(painted<0.2)
	history.undo(); assert(village.density_at(Vector2.ZERO)==1.0); history.redo(); assert(is_equal_approx(village.density_at(Vector2.ZERO),painted))
	plugin._reset_density(1); assert(village.density_at(Vector2.ZERO)==1.0)
	plugin._draw(3); assert(plugin.mode==3 and plugin.draft.kind==3); plugin._cancel()
	plugin._draw(4)
	for p in [Vector3(-4,0,-4),Vector3(4,0,-4),Vector3(4,0,4),Vector3(-4,0,4)]:
		var click := InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=camera.unproject_position(village.to_global(p)); plugin._forward_3d_gui_input(camera,click)
	plugin._finish_drawing(); plugin._selection(); assert(village.guides(4).size()==1,"Court not created"); assert(plugin.tabs.current_tab==4,"Court context tab incorrect")
	history.undo(); assert(village.guides(4).is_empty())
	plugin._organic_mode(); assert(village.layout_mode==1); history.undo(); assert(village.layout_mode==0)
	print("VILLAGE_EDITOR_PAINT_UNDO_EXCLUSION_COURT_MODE_OK")

	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(village.guides(1)[0]); plugin._selection()
	assert(plugin.tabs.current_tab==1 and plugin.gizmos.focus==village.guides(1)[0])
	var road=village.guides(1)[0]; var points: PackedVector2Array=road.points.duplicate()
	plugin._add_point(); assert(road.points.size()==3); history.undo(); assert(road.points==points); history.redo()
	plugin.tabs.current_tab=2; assert(plugin.gizmos.focus==null,"Inactive context still shows point handles")
	plugin._generate(); assert(not village.failed,village.report); assert(village.lots().size()>0)
	var count: int=village.lots().size(); var first=village.lots()[0]
	history.undo(); assert(village.lots().is_empty()); history.redo(); assert(village.lots().size()==count and village.lots()[0]==first)
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(first); plugin._lock(); assert(first.locked); history.undo(); assert(not first.locked)
	var packed: PackedScene=plugin._snapshot_village(village); assert(packed!=null)
	var preview=packed.instantiate(); assert(preview.lots().size()==village.lots().size()); preview.free()
	print("VILLAGE_EDITOR_CONTEXT_POINTS_GENERATE_LOCK_PLAY_SNAPSHOT_UNDO_OK")
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
