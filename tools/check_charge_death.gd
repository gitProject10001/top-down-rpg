extends "res://tools/check_pack_combat.gd"
func run() -> void:
	# This fixture measures charge multipliers, independently of random critical hits.
	get_node("/root/Traits")._mods["crit"] = -1.0
	world = Node3D.new()
	add_child(world)
	box("Floor", Vector3(0,-.25,0), Vector3(20,.5,20))
	var hero := Hero.instantiate() as Player
	hero.position = Vector3(0,1,0)
	world.add_child(hero)
	hero.intent.set_physics_process(false)
	hero.stamina_regen = 0
	await frames(20)
	var attack = hero.get_node("StateMachine/Attack")
	var hits: Array[int] = []
	attack.damage_window_opened.connect(func(_step: int, _dur: float): hits.append(hero.sword._hitbox.damage))
	hero.intent._sample_attack_button(true)
	await frames(45)
	check(hits.is_empty(), "charge cannot hit while preparing")
	check(attack.charge_elapsed >= .65, "charge reaches threshold")
	check(hero._tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS,"held pose remains evaluated in physics")
	check(hero._tree["parameters/Slash/ActionClock/scale"] == 0.0,"only action clock is paused")
	hero.intent._sample_attack_button(false)
	await frames(30)
	check(attack._clip == "atk_dash", "charged release uses authored horizontal lunge")
	check(hits.size() == 1 and hits[0] >= 2, "release gives one powered hit")
	check(is_equal_approx(hero.stamina,150), "charge costs stamina once")
	hero.intent._sample_attack_button(true)
	hero.intent._sample_attack_button(false)
	await frames(35)
	check(hits.size() == 2 and hits[1] < hits[0], "tap restores ordinary damage")
	hero.intent._sample_attack_button(true)
	await frames(12)
	var dodge := InputEventAction.new()
	dodge.action="dash"
	dodge.pressed=true
	attack.handle_input(dodge)
	check(hero.state_name()=="Dash", "dodge cancels charge")
	hero.intent._sample_attack_button(false)
	await frames(30)
	check(hits.size()==2, "cancelled charge has no hit")
	check(hero._tree.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS,"charge cancellation restores animation")
	hero.stamina = 10
	hero.intent._sample_attack_button(true)
	await frames(45)
	hero.intent._sample_attack_button(false)
	await frames(35)
	check(hits.size()==3 and hits[2]==hits[1], "insufficient stamina releases normal damage")
	check(is_equal_approx(hero.stamina,10), "insufficient stamina cannot overspend")
	hero.queue_free()
	await frames(2)
	await death_case(false, false)
	await death_case(true, false)
	await death_case(false, true)
	print("CHARGE_DEATH_CHECK failures=", failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(1 if failures else 0)
func death_case(wall: bool, heavy: bool) -> void:
	var enemy := Raider.instantiate() as EnemyDuelist
	enemy.position=Vector3(0,1,0)
	world.add_child(enemy)
	enemy.intent.set_physics_process(false)
	await frames(20)
	var obstacle: Node3D
	if wall: obstacle=box("Wall",Vector3(0,1,.55),Vector3(3,2,.15))
	var source:=Node3D.new()
	world.add_child(source)
	source.position=Vector3(0,1,-1)
	source.set_meta("finisher",heavy)
	var origin:=enemy.global_position
	enemy.health.take_damage(100,source)
	await frames(3)
	check(enemy.health.hp==0 and enemy.state_name()=="Dead", "step is presentation of an already dead enemy")
	check(enemy.death_stepping == (not wall and not heavy), "wall/heavy hit skips death step")
	if enemy.death_stepping:
		get_tree().paused=true
		var paused_position:=enemy.global_position
		await frames(8)
		check(enemy.global_position==paused_position,"pause stops death step")
		get_tree().paused=false
	await frames(30)
	var rag=enemy.find_child("Ragdoll",true,false)
	check(rag.is_simulating_physics(),"death step hands off to ragdoll")
	check(enemy.global_position.distance_to(origin)<.45,"death step distance bounded")
	check(not enemy.sword._hitbox._active,"dead enemy cannot hit")
	enemy.queue_free()
	source.queue_free()
	if obstacle: obstacle.queue_free()
	await frames(2)
