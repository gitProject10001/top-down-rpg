@tool
extends RefCounted
func run(plugin: EditorPlugin) -> void:
 for i in 80: await plugin.get_tree().process_frame
 var request=preload("res://addons/castle_generator/request.gd").new()
 request.seed_value=17
 var plan=preload("res://addons/castle_generator/planner.gd").generate(request).plan
 plugin._create_composed_castle(plan)
 var group=EditorInterface.get_selection().get_selected_nodes()[0]
 var keep=group.get_node("Mastio")
 keep.position.z+=0.1; keep.rotation.y=0.025
 var container := Node3D.new(); container.name="Volumes"; keep.add_child(container); container.owner=EditorInterface.get_edited_scene_root()
 var accessory=preload("res://addons/house_builder/volume.gd").new(); accessory.attached=false; accessory.width=2; accessory.depth=2; accessory.position.z=2
 container.add_child(accessory); accessory.owner=container.owner
 for i in 5: await plugin.get_tree().process_frame
 EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(keep)
 plugin._toggle_composition_lock(); plugin._refresh_composition_elements()
 assert("bloccata" in plugin.composition_panel.element_info.text)
 var position: Vector3=keep.position
 plugin._release_composition_position()
 assert(not keep.get_meta("composition_locked") and keep.position==position)
 var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(group))
 history.undo(); assert(keep.get_meta("composition_locked"))
 history.redo(); assert(not keep.get_meta("composition_locked"))
 plugin._preview_castle_regeneration(plan)
 var dialog: ConfirmationDialog
 for node in EditorInterface.get_base_control().get_children():
  if node is ConfirmationDialog and node.title=="Rigenerazione · disposizione interna": dialog=node
 assert(dialog!=null,"Valid oriented body/accessory opens confirmation")
 var expected=preload("res://addons/castle_generator/regeneration.gd").propose(group,plan)
 dialog.confirmed.emit()
 assert(group.get_meta("composition_plan")==expected.plan)
 assert(keep.rotation.y>0.02 and is_instance_valid(accessory))
 history.undo(); assert(keep.position==position)
 history.redo(); assert(group.get_meta("composition_plan")==expected.plan)
 print("CASTLE_REAL_EDITOR_SELECTION_LOCK_RELEASE_REGEN_UNDO_REDO_OK")
 plugin.get_tree().quit()
