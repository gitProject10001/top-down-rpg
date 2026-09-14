extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var play=preload("res://scripts/village/rock_terrace_play.gd").new(); root.add_child(play)
 for i in 30: await physics_frame
 var standing_height: float=play.player.position.y
 await play.walk(Vector3(0,0,9),180)
 print("RAMP_MIDPOINT ",play.player.position)
 assert(play.player.position.y-standing_height>1.2 and play.player.position.y-standing_height<1.9,"Player must stand halfway up ramp")
 if DisplayServer.get_name()!="headless":
  await process_frame; await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://captures/balcony_attachment/rock_terrace_ramp_play.png")
 await play.walk(Vector3(0,0,3),200)
 assert(play.player.position.z<3.5 and absf(play.player.position.y-standing_height-3)<0.15,"Player must reach plateau without teleport")
 await play.walk(Vector3(0,0,14),240)
 assert(play.player.position.z>13.5 and absf(play.player.position.y-standing_height)<0.15,"Player must descend to ground")
 print("ROCK_TERRACE_PLAYER_ASCEND_DESCEND_OK")
 quit()
