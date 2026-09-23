extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate(); root.add_child(scene)
 for i in 45: await physics_frame
 var view=scene.get_node("GameplayPreviewRig/Pixel/View")
 for name in ["Affioramento_0","Affioramento_1"]:
  var cliff=view.get_node(name+"/ContinuousCliff")
  assert(cliff.layered_rock_wall)
  var updated: Dictionary=cliff.generate()
  assert(not updated.has("error"),str(updated.get("error")))
  cliff.layered_rock_wall=false
  var previous: Dictionary=cliff.generate()
  cliff.layered_rock_wall=true; cliff.rebuild()
  assert(updated.elevated.top_vertices==previous.elevated.top_vertices,"Plateau and ramps remain unchanged")
  assert(updated.faces!=previous.faces,"Wall geometry actually replaced")
  assert(not cliff._invades_corridor(updated.vertices,updated.indices,updated.corridor),"Walkway stays clear")
  print("INTEGRATED_ROCK_WALL ",name," triangles=",updated.triangles," plateau_and_ramps_unchanged=true")
 if DisplayServer.get_name()!="headless":
  scene.camera.set_process(false); scene.camera.set_physics_process(false)
  scene.camera.perspective_fov=0; scene.camera.size=35
  scene.camera.global_position=Vector3(-43,15,-31); scene.camera.look_at(Vector3(-46,3,-57))
  for i in 10: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/integrated_rock_wall.png")
 scene.queue_free(); await process_frame; await process_frame; quit()
