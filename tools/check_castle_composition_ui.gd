extends SceneTree
var emitted: Dictionary={}
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size=Vector2i(520,900)
 var panel=preload("res://addons/castle_generator/editor_panel.gd").new()
 panel.position=Vector2(24,24); panel.size=Vector2(340,680); root.add_child(panel)
 panel.create_requested.connect(func(plan): emitted=plan)
 await process_frame
 assert(not panel.current_plan.is_empty() and not panel.create_button.disabled)
 var root_count := root.get_child_count()
 var original: Dictionary=panel.current_plan.duplicate(true)
 panel.seed_input.value+=1
 assert(panel.current_plan!=original)
 panel.seed_input.value-=1
 assert(panel.current_plan==original)
 panel.create_button.pressed.emit()
 assert(emitted==original)
 panel.open_input.value=100
 assert(panel.current_plan.is_empty() and panel.create_button.disabled)
 assert(not panel.info.text.is_empty())
 panel.open_input.value=65
 assert(panel.current_plan==original)
 assert(root.get_child_count()==root_count,"Preview must not instantiate castles")
 print("CASTLE_UI_SEED_PREVIEW_ERRORS_CREATE_SIGNAL_OK")
 if DisplayServer.get_name()!="headless":
  for frame in 5: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/castle_composition_ui.png")
 panel.free(); quit()
