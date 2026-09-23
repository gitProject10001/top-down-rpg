extends "res://tools/check_pack_combat.gd"
class LockRig extends Node3D:
	var target: Node3D
	func locked() -> Node3D: return target
func run() -> void:
	world=Node3D.new()
	add_child(world)
	box("Floor",Vector3(0,-.25,0),Vector3(30,.5,30))
	var hero:=Hero.instantiate() as Player
	hero.position=Vector3(0,1,0)
	world.add_child(hero)
	hero.intent.set_physics_process(false)
	await frames(20)
	check(hero._locomotion_layers,"locomotion layers installed")
	check(hero.movement_speed()==6,"outside defaults to run")
	hero.indoors=true
	check(is_equal_approx(hero.movement_speed(),2.2),"indoors defaults to walk")
	Input.action_press("walk_modifier")
	check(hero.movement_speed()==6,"explicit indoor run override")
	hero.indoors=false
	check(is_equal_approx(hero.movement_speed(),2.2),"outdoor walk modifier")
	Input.action_release("walk_modifier")
	hero.velocity=Vector3.ZERO
	hero.apply_movement(Vector2(.3,0),1)
	check(is_equal_approx(hero.velocity.x,1.8),"analog magnitude is preserved")
	var rig:=LockRig.new()
	rig.add_to_group("camera_rig")
	world.add_child(rig)
	rig.target=actor_at("LockTarget",Vector3(0,1,-6))
	for direction in [Vector2(0,1),Vector2(-1,0),Vector2(1,0)]:
		hero.visuals.rotation=Vector3.ZERO
		hero.velocity=Vector3(direction.x*3,0,direction.y*3)
		hero.get_node("StateMachine").set_physics_process(false)
		hero.face_aim_direction(.2)
		hero._process(.016)
		var blend:Vector2=hero._tree["parameters/Move/Walk/blend_position"]
		check(blend.distance_to(Vector2(direction.x,-direction.y))<.05,"locked animation follows facing-relative movement")
		check(hero._tree["parameters/Move/Locked/blend_amount"]==1,"lock uses strafe layers")
	hero.queue_free()
	rig.target.queue_free()
	rig.queue_free()
	await frames(2)
	await recovery_case(false)
	await recovery_case(true)
	print("LOCOMOTION_CHECK failures=",failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(1 if failures else 0)
func recovery_case(wall: bool) -> void:
	var enemy:=Raider.instantiate() as Player
	enemy.position=Vector3(0,1,0)
	world.add_child(enemy)
	enemy.intent.set_physics_process(false)
	await frames(20)
	var obstacle:Node3D
	if wall: obstacle=box("BackWall",Vector3(0,1,.55),Vector3(3,2,.15))
	var source:=Node3D.new()
	world.add_child(source)
	source.position=Vector3(0,1,-1)
	source.set_meta("swing_dir",SwingDir.NONE)
	source.set_meta("recovery_step",true)
	var origin:=enemy.global_position
	enemy.health.take_damage(1,source)
	var hurt:Node=enemy.get_node("StateMachine/Hurt")
	check(hurt.recovery_step,"second stroke requests recovery step")
	await frames(35)
	var travel:=enemy.global_position.z-origin.z
	check(travel<.25 if wall else travel>.2 and travel<.6,"step respects distance and wall")
	check(enemy.state_name()=="Idle","recovery returns to idle")
	print("RECOVERY wall=",wall," distance=",travel)
	enemy.queue_free()
	source.queue_free()
	if obstacle: obstacle.queue_free()
	await frames(2)
