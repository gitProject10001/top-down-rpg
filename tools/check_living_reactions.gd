extends "res://tools/check_pack_combat.gd"
func run() -> void:
	world=Node3D.new()
	add_child(world)
	box("Floor", Vector3(0,-.25,0),Vector3(20,.5,20))
	var enemy:=Raider.instantiate() as Player
	enemy.position=Vector3(0,1,0)
	enemy.get_node("Health").max_hp=40
	world.add_child(enemy)
	enemy.intent.set_physics_process(false)
	await frames(20)
	var hurt: Node=enemy.get_node("StateMachine/Hurt")
	var source:=Node3D.new()
	world.add_child(source)
	source.position=Vector3(0,1,-1)
	source.set_meta("swing_dir",SwingDir.NONE)
	var skel:=enemy.find_child("GeneralSkeleton",true,false) as Skeleton3D
	source.set_meta("contact_point",skel.to_global(skel.get_bone_global_pose(skel.find_bone("Head")).origin))
	enemy.health.take_damage(1,source)
	check(hurt.reaction_clip=="hurt_head","head contact selects head flinch")
	await frames(30)
	source.set_meta("contact_point",enemy.global_position)
	enemy.health.take_damage(1,source)
	check(hurt.reaction_clip=="hurt_chest","lower contact selects chest flinch")
	await frames(30)
	source.set_meta("finisher",true)
	source.set_meta("swing_dir",SwingDir.NONE)
	enemy.health.take_damage(1,source)
	check(hurt.knocked_down and hurt.reaction_clip=="hurt_knockback","surviving finisher starts fall")
	check(not enemy.sword.get_node("HitBox")._active,"fall closes weapon")
	await frames(20)
	var elapsed: float=hurt._elapsed
	enemy.health._invuln_until=0
	enemy.health.take_damage(1,source)
	check(hurt._elapsed>=elapsed,"follow-up damage does not restart fall")
	await frames(18)
	check(hurt.recovering and hurt.reaction_clip=="getup","fall transitions into getup")
	var at: float=hurt._elapsed
	get_tree().paused=true
	for i in 8: await get_tree().process_frame
	check(is_equal_approx(hurt._elapsed,at),"pause freezes getup")
	get_tree().paused=false
	await frames(48)
	check(enemy.state_name()=="Idle" and is_equal_approx(enemy._action_playback_speed,1),"getup returns control and restores animation clock")
	check(enemy.global_position.distance_to(Vector3(0,.87,0))<1,"fall does not drift away from body collider")
	enemy.health._invuln_until=0
	enemy.health.take_damage(1,source)
	await frames(15)
	enemy.health._invuln_until=0
	enemy.health.take_damage(100,source)
	await frames(4)
	check(enemy.state_name()=="Dead" and enemy.find_child("Ragdoll",true,false).is_simulating_physics(),"death interrupts fall into physical ragdoll")
	print("LIVING_REACTIONS_CHECK failures=",failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(1 if failures else 0)
