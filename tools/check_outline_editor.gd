@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
 for i in 60: await plugin.get_tree().process_frame
 plugin._create_polygon_tower()
 var tower=EditorInterface.get_selection().get_selected_nodes()[0]
 tower.width=8; tower.depth=8; tower.edit_outline=true
 for i in 6: await plugin.get_tree().process_frame
 var gizmo := EditorNode3DGizmo.new(); gizmo.set_node_3d(tower)
 var controller=plugin.outline_gizmos
 var before=controller._get_handle_value(gizmo,0,false)
 var camera=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
 var point: Vector3=tower.footprint_vertices()[0]+Vector3(-0.2,0,0.1)
 controller._set_handle(gizmo,0,false,camera,camera.unproject_position(tower.to_global(point)))
 assert(not tower.custom_outline.is_empty(),"Real gizmo projection changes outline")
 var changed: PackedVector2Array=tower.custom_outline.duplicate()
 controller._commit_handle(gizmo,0,false,before,false)
 var undo=plugin.get_undo_redo()
 var history=undo.get_history_undo_redo(undo.get_object_history_id(tower))
 history.undo(); assert(tower.custom_outline==before)
 history.redo(); assert(tower.custom_outline==changed)
 controller._commit_handle(gizmo,0,false,before,true)
 assert(tower.custom_outline==before,"Cancel restores regular outline")
 print("OUTLINE_REAL_EDITOR_GIZMO_UNDO_REDO_CANCEL_OK")
 plugin.get_tree().quit()
