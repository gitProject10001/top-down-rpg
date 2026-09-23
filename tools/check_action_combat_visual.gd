extends "res://tools/check_borgo_recipes.gd"
var living_captured := false
func run() -> void:
 scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
 get_tree().root.add_child(scene)
 await settle(60)
 await scene.combat_encounter.reset_encounter(true)
 await settle(25)
 var hero: Player=scene.player
 hero.intent.set_physics_process(false)
 hero.intent.clear()
 hero.health.extend_invulnerable(60)
 var foe: Player=scene.combat_encounter.fighters[0]
 for enemy in scene.combat_encounter.fighters:
  enemy.intent.set_physics_process(false)
  enemy.intent.clear()
  enemy.get_node("StateMachine").transition_to("Idle")
 foe.global_position=hero.global_position+Vector3(0,0,-1.2)
 foe.health.max_hp=20
 foe.health.revive()
 hero.intent.look=Vector2(0,-1)
 hero.visuals.rotation.y=0
 scene.camera._apply(true)
 await settle(15)
 var attack: Node=hero.get_node("StateMachine/Attack")
 var hits: Array[int]=[]
 attack.damage_window_opened.connect(func(index: int, _duration: float):
  hits.append(index)
  if index < 2:
   hero.intent._sample_attack_button(true)
   hero.intent._sample_attack_button(false)
  if index == 0: snap.call_deferred("action_slash")
  if index == 2: living_sequence.call_deferred()
 )
 hero.intent._sample_attack_button(true)
 hero.intent._sample_attack_button(false)
 for i in 400:
  await settle(1)
  if living_captured: break
 check(living_captured,"living reaction captured before lethal fixture")
 await settle(45)
 check(hits == [0,1,2], "integrated click phrase has three contacts")
 foe.health.set_invulnerable(false)
 foe.health._invuln_until=0
 foe.health.take_damage(100, hero.sword.get_node("HitBox"))
 await settle(8)
 await snap("action_ragdoll_early")
 await settle(16)
 await snap("action_ragdoll_collapse")
 await settle(86)
 await snap("action_ragdoll")
 check(foe.find_child("Ragdoll",true,false).is_simulating_physics(),"integrated enemy death uses physics")
 print("ACTION_VISUAL_RESULT ",failures)
 scene.queue_free()
 await settle(3)
 get_tree().quit(0 if failures.is_empty() else 1)

func snap(label: String) -> void:
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://captures/"+label+".png")

func living_sequence() -> void:
 var foe: Player=scene.combat_encounter.fighters[0]
 var hurt: Node=foe.get_node("StateMachine/Hurt")
 for i in 150:
  await settle(1)
  if hurt.knocked_down and not hurt.recovering and hurt._elapsed >= hurt.fall_duration*.7:
   await snap("action_knockdown")
   break
 for i in 150:
  await settle(1)
  if hurt.recovering and hurt._elapsed >= hurt.rise_duration*.45:
   await snap("action_getup")
   living_captured=true
   break
