extends "res://tools/check_pack_combat.gd"
func run() -> void:
	world = Node3D.new()
	add_child(world)
	box("Floor", Vector3(0,-.25,0), Vector3(30,.5,30))
	box("Step", Vector3(5,.15,0), Vector3(1,.3,3))
	await frames(3)
	for scenario in ["left_shoulder", "right_shoulder", "knee", "moving_step"]:
		await reaction_case(scenario)
	print("RAGDOLL_REACTION_CHECK failures=", failures)
	world.queue_free()
	await frames(2)
	get_tree().quit(1 if failures else 0)

func reaction_case(scenario: String) -> void:
	var enemy := Raider.instantiate() as Player
	enemy.position = Vector3(4.2 if scenario == "moving_step" else 0.0, 1, 0)
	world.add_child(enemy)
	enemy.intent.set_physics_process(false)
	await frames(20)
	var rag: Node = enemy.find_child("Ragdoll",true,false)
	var label := "RightUpperArm" if scenario == "right_shoulder" else "LeftUpperArm"
	if scenario == "knee": label = "LeftLowerLeg"
	var bone := rag.get_node("pb_"+label) as PhysicalBone3D
	var source := Node3D.new()
	world.add_child(source)
	source.global_position = enemy.global_position + Vector3.FORWARD
	source.set_meta("contact_point", bone.global_position)
	source.set_meta("impact_direction", Vector3.LEFT if scenario == "right_shoulder" else Vector3.RIGHT)
	source.set_meta("finisher", scenario == "moving_step")
	var incoming := Vector3(2,0,.3) if scenario == "moving_step" else Vector3.ZERO
	enemy.velocity = incoming
	enemy.health.take_damage(100,source)
	await frames(4)
	check(rag.impact_bone == label, scenario+": closest limb receives impact")
	check(rag.seeded_velocity.is_equal_approx(incoming), scenario+": original locomotion preserved before Hurt")
	var hips := rag.get_node("pb_Hips") as PhysicalBone3D
	check(hips.elapsed > 0 and hips.active_reaction, scenario+": posture resistance actually runs in physics callback")
	var paused_at: float = hips.elapsed
	get_tree().paused = true
	for i in 8: await get_tree().process_frame
	check(is_equal_approx(hips.elapsed,paused_at),scenario+": game pause freezes reaction")
	get_tree().paused = false
	await frames(160)
	for physical in rag.get_children():
		check(physical.global_position.is_finite() and physical.global_position.distance_to(enemy.global_position) < 6,scenario+": bounded "+String(physical.bone_name))
		check(not physical.active_reaction, scenario+": muscles fully release")
		if physical.joint_type == PhysicalBone3D.JOINT_TYPE_6DOF:
			check(is_zero_approx(physical.get("joint_constraints/z/angular_spring_stiffness")),scenario+": limb spring released")
	check(hips.global_position.y > -.2 and hips.global_position.y < 1,scenario+": rests on terrain")
	print("REACTION ",scenario," bone=",rag.impact_bone," hips=",hips.global_position," speed=",hips.linear_velocity.length())
	enemy.queue_free()
	source.queue_free()
	await frames(2)
