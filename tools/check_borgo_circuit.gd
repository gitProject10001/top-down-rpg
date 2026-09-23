extends "res://tools/check_borgo_recipes.gd"
func run() -> void:
 scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
 scene.combat_encounter_enabled=true
 get_tree().root.add_child(scene)
 await settle(90)
 var view: Node=scene.get_node("GameplayPreviewRig/Pixel/View")
 var trial: Node=view.get_node("BorgoCircuit")
 trial.combat_enabled=true
 var route: Node=view.get_node("ExplorationRoute")
 check(view.get_node("Borgo").known_ids.size()==6,"six original village lots retained")
 check(view.has_node("TorreDelGuado"),"authored House Builder tower")
 scene.player.health.extend_invulnerable(240)
 scene.player.global_position=Vector3(15,1,23); scene.player.velocity=Vector3.ZERO
 await settle(30)
 check(trial.step==1,"trial starts at existing village exit")
 check(not trial.has_node("SegnaleBorgo") and route.branches.size()==1,"no signs or redundant return fork")
 for p in route.branches[0]:
  var reached:=await move_to(Vector3(p.x,.18,p.y),.6,500)
  check(reached,"outward path blocked at "+str(p)+" from "+str(scene.player.global_position))
  if not reached: break
  if p==Vector2(-12,20):
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("res://captures/circuit_junction.png")
 await settle(30)
 for enemy in scene.combat_encounter.fighters:
  check(not enemy.get_node("DuelBrain")._engaged,"tower route does not engage old meadow encounter")
 check(trial.step==2,"tower checkpoint waits for encounter")
 check(is_instance_valid(trial.encounter) and trial.encounter.fighters.size()==2,"two enemies use existing pack combat")
 if is_instance_valid(trial.encounter):
  for fighter in trial.encounter.fighters:
   fighter.health.set_invulnerable(false)
   fighter.health.take_damage(100)
 await settle(100)
 check(trial.step==3,"defeating tower enemies enables return")
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://captures/circuit_tower.png")
 var back: PackedVector2Array=route.branches[0].duplicate()
 back.reverse()
 for p in back:
  var reached:=await move_to(Vector3(p.x,.18,p.y),.6,500)
  check(reached,"return path blocked at "+str(p)+" from "+str(scene.player.global_position))
  if not reached: break
 await settle(5)
 check(trial.step==4,"complete loop returns to existing village")
 print("CIRCUIT_TRAVERSAL metres=",trial.travelled," seconds=",trial.elapsed," splits=",trial.split_times)
 await performance()
 scene.camera._target=null; scene.camera._focus=Vector3(-20,0,34); scene.camera.ortho_size=100; scene.camera._apply(true)
 await settle(60)
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://captures/circuit_overview.png")
 print("BORGO_CIRCUIT_RESULT ",failures)
 scene.queue_free(); await settle(3)
 get_tree().quit(0 if failures.is_empty() else 1)
