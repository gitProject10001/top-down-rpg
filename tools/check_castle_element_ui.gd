extends SceneTree
const Service=preload("res://addons/castle_generator/regeneration.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size=Vector2i(740,700)
 var request=preload("res://addons/castle_generator/request.gd").new()
 var plan=preload("res://addons/castle_generator/planner.gd").generate(request).plan
 var group=preload("res://addons/castle_generator/materializer.gd").create(plan)
 var keep=group.get_node("Mastio")
 var panel=preload("res://addons/castle_generator/editor_panel.gd").new()
 panel.position=Vector2(20,20); panel.size=Vector2(700,640); root.add_child(panel)
 await process_frame
 panel.update_elements(group,"keep")
 assert(panel.reset_button.disabled and not panel.lock_button.disabled)
 keep.position.z+=0.1
 panel.update_elements(group,"keep")
 assert(not panel.reset_button.disabled and "manuale" in panel.element_info.text)
 keep.set_meta("composition_locked",true)
 panel.update_elements(group,"keep")
 assert("bloccata" in panel.element_info.text and panel.lock_button.text=="Sblocca posizione")
 var position: Vector3=keep.position
 var doors=keep.openings.duplicate(true)
 var old: Dictionary=group.get_meta("composition_baseline",{}).duplicate(true)
 var undo := UndoRedo.new(); undo.create_action("Release")
 undo.add_do_method(group.set_meta.bind("composition_baseline",Service.release_baseline(group,"keep")))
 undo.add_do_method(keep.set_meta.bind("composition_locked",false))
 undo.add_undo_method(group.set_meta.bind("composition_baseline",old))
 undo.add_undo_method(keep.set_meta.bind("composition_locked",true))
 undo.commit_action(); panel.update_elements(group,"keep")
 assert(panel.reset_button.disabled and "automatica" in panel.element_info.text)
 assert(keep.position==position and keep.openings==doors)
 undo.undo(); panel.update_elements(group,"keep")
 assert("bloccata" in panel.element_info.text)
 undo.redo(); assert(not keep.get_meta("composition_locked"))
 panel.update_elements(group,"TorreOvest")
 assert(panel.reset_button.disabled and panel.lock_button.disabled)
 undo.undo(); panel.update_elements(group,"keep")
 panel.get_child(0).current_tab=1
 if DisplayServer.get_name()!="headless":
  for frame in 5: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/castle_element_states.png")
 panel.update_elements(null,"")
 assert(panel.elements.item_count==0 and panel.reset_button.disabled)
 undo.clear_history(); undo.free(); panel.free(); group.free()
 print("CASTLE_ELEMENT_STATUS_RELEASE_UNDO_REDO_NO_MOVEMENT_OK")
 quit()
