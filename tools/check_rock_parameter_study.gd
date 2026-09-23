extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var scene = load("res://scenes/dev/rock_parameter_study.tscn").instantiate()
 root.add_child(scene); current_scene=scene
 var player=scene.get_node("GameplayPreviewRig/Pixel/View/Player")
 for i in 40: await physics_frame
 var grounded: bool=player.is_on_floor()
 var start: Vector3=player.global_position
 Input.action_press("move_right")
 for i in 50: await physics_frame
 Input.action_release("move_right")
 var moved: bool=player.global_position.distance_to(start)>1.0
 var camera=scene.get_node("GameplayPreviewRig/Pixel/View/IsoCam")
 var following: bool=camera.target_path==NodePath("../Player")
 print("ROCK_STUDY grounded=",grounded," moved=",moved," game_camera=",following)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/rock_parameter_study_play.png")
 current_scene=null; scene.queue_free(); await process_frame
 quit(0 if grounded and moved and following else 1)
