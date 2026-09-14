extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var play=preload("res://scripts/village/domed_terrace_play.gd").new(); root.add_child(play)
 for i in 30: await physics_frame
 var standing_height: float=play.player.position.y
 await play.walk(Vector3(0,0,3),300)
 assert(absf(play.player.position.y-standing_height-3.18)<0.18,"Reach terrace by exterior stair")
 await play.walk(Vector3(0,0,0),180)
 assert(play.inside,"Enter dome pavilion through real opening")
 assert(not play.pavilion._generated.get_node("Roof").visible,"Dome hides only inside")
 if DisplayServer.get_name()!="headless":
  await process_frame; await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/domed_terrace_inside.png")
 await play.walk(Vector3(0,0,3),180)
 assert(not play.inside and play.pavilion._generated.get_node("Roof").visible)
 await play.walk(Vector3(0,0,14),350)
 assert(play.player.position.z>13.5 and absf(play.player.position.y-standing_height)<0.18,"Return to ground")
 print("DOMED_TERRACE_STAIRS_PAVILION_ROUNDTRIP_OK")
 quit()
