extends "res://tools/check_borgo_recipes.gd"
func run() -> void:
 scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
 get_tree().root.add_child(scene)
 await settle(60)
 await scene.combat_encounter.reset_encounter(true)
 var hero:Player=scene.player
 hero.intent.set_physics_process(false)
 hero.intent.clear()
 var origin:Vector3=hero.global_position
 for enemy in scene.combat_encounter.fighters:
  enemy.intent.set_physics_process(false)
  enemy.intent.clear()
 var foe:Player=scene.combat_encounter.fighters[0]
 foe.global_position=origin+Vector3(0,0,-5)
 scene.camera._lock_target=foe
 await settle(15)
 for mode in ["walk","run"]:
  if mode=="walk": Input.action_press("walk_modifier")
  else: Input.action_release("walk_modifier")
  for item in [["forward",Vector2(0,-1)],["back",Vector2(0,1)],["left",Vector2(-1,0)],["right",Vector2(1,0)]]:
   hero.global_position=origin
   hero.velocity=Vector3.ZERO
   hero.visuals.rotation=Vector3.ZERO
   hero.intent.move=item[1]
   await settle(22)
   check(hero.combat_lock_target()==foe,"lock remains valid during "+mode+item[0])
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("res://captures/locomotion_"+mode+"_"+item[0]+".png")
 hero.intent.move=Vector2.ZERO
 Input.action_release("walk_modifier")
 var house:Node3D=scene.plans[0].house()
 hero.global_position=house.to_global(Vector3(0,1,0))
 hero.velocity=Vector3.ZERO
 await settle(4)
 check(hero.indoors and is_equal_approx(hero.movement_speed(),hero.walk_speed),"existing interior detection sets walk")
 hero.global_position=origin
 await settle(4)
 check(not hero.indoors,"exit restores outdoor context")
 print("LOCOMOTION_VISUAL_RESULT ",failures)
 scene.queue_free()
 await settle(3)
 get_tree().quit(0 if failures.is_empty() else 1)
