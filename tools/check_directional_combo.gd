extends SceneTree
## Real PlayerIntent events -> player3 FSM -> animation clock -> swept Sword contact.
## Run: godot --headless --path . --script tools/check_directional_combo.gd
var world: Node3D
var hero: CharacterBody3D
var attack: Node
var hitbox: Area3D
var dummy_health: Node
var starts: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var contacts: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("COMBO_CHECK: " + message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func action(key: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = key
	event.pressed = pressed
	Input.parse_input_event(event)

func tap() -> void:
	action("attack", true)
	await frames(1)
	action("attack", false)

func reset_case() -> void:
	action("attack", false)
	action("dash", false)
	action("block", false)
	await frames(80)
	hero.intent.clear()
	hero.stamina = hero.max_stamina
	hero.global_position = Vector3(0, .88, 0)
	hero.velocity = Vector3.ZERO
	hero.visuals.rotation.y = 0.0
	hero._dash_ready_at = 0.0
	starts.clear()
	windows.clear()
	contacts.clear()

func run() -> void:
	world = Node3D.new()
	world.name = "ComboAcceptance"
	root.add_child(world)
	current_scene = world
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	hero = load("res://scenes/player/player3.tscn").instantiate()
	hero.position = Vector3(0, .88, 0)
	world.add_child(hero)
	attack = hero.get_node("StateMachine/DirAttack")
	hitbox = hero.sword.get_node("HitBox")
	attack.combo_step_started.connect(func(index: int, direction: int, clip: String):
		starts.append({"step": index, "direction": direction, "clip": clip,
			"contact": attack._len * attack._strike, "duration": attack._len,
			"cancel": attack._len * attack._cancel})
	)
	attack.damage_window_opened.connect(func(index: int, duration: float):
		windows.append({"step": index, "duration": duration,
			"finisher": hitbox.get_meta("finisher", false), "position": hero.global_position})
		check(hitbox._active, "Damage window signal must coincide with a live sword")
		check(attack._t >= attack._len * attack._strike, "No early damage during windup")
	)
	# A broad stationary receiver isolates cadence from enemy footwork. These
	# contacts still come from the real animated blade's physics sweep.
	var dummy := Node3D.new()
	dummy.name = "ContactReceiver"
	dummy.position.y = 1.2
	dummy_health = load("res://scripts/components/health.gd").new()
	dummy_health.name = "Health"
	dummy_health.max_hp = 100
	dummy.add_child(dummy_health)
	var hurt: Area3D = load("res://scripts/components/hurtbox.gd").new()
	hurt.name = "HurtBox"
	hurt.collision_layer = 4
	hurt.collision_mask = 0
	var receiver := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 8.0
	receiver.shape = sphere
	hurt.add_child(receiver)
	dummy.add_child(hurt)
	world.add_child(dummy)
	dummy_health.damaged.connect(func(amount: int, _source: Node):
		contacts.append({"step": attack.combo_index(), "amount": amount})
		check(hitbox._active and attack._phase == attack.Phase.SWING, "Contact outside committed sword window")
	)
	await frames(20)
	if "--range-only" in OS.get_cmdline_user_args():
		var capsule := CapsuleShape3D.new()
		capsule.radius = .5
		capsule.height = 1.3281
		receiver.shape = capsule
		for distance in [1.3, 1.6, 8.0]:
			await reset_case()
			dummy.position = Vector3(0, .88, -distance)
			await frames(3)
			await tap()
			await frames(6)
			await tap()
			for frame in 50:
				if starts.size() >= 2: break
				await frames(1)
			await frames(6)
			await tap()
			await frames(90)
			print("COMBO_CAPSULE_RANGE distance=", distance, " contacts=", contacts)
			if distance < 2.0:
				check(contacts.size() == 3, "All three cuts should reach a normally sized capsule at %.2f m" % distance)
			else:
				check(contacts.is_empty(), "A distant target must remain a miss")
				check(hero.global_position.distance_to(Vector3(0, .88, 0)) < 1.1, "The three steps must not become an auto-closing lunge")
		print("DIRECTIONAL_COMBO_RANGE_RESULT failures=", failures.size())
		world.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	# A complete press/release between physics frames must still produce one hit.
	action("attack", true)
	action("attack", false)
	await frames(55)
	check(starts.size() == 1 and windows.size() == 1 and contacts.size() == 1,
		"An inter-frame click must survive, exactly once")
	check(not hitbox._active, "Hitbox closes after its finite active window")
	await reset_case()
	# Each extra press arrives before contact/recovery, exercising real buffering.
	await tap()
	await frames(6)
	await tap()
	for frame in 50:
		if starts.size() >= 2: break
		await frames(1)
	await frames(6)
	await tap()
	await frames(100)
	check(starts.size() == 3, "Three presses must form exactly three steps")
	check(windows.size() == 3 and contacts.size() == 3, "One real contact per step, no duplicate window damage")
	if starts.size() == 3:
		check(starts[0].step == 0 and starts[1].step == 1 and starts[2].step == 2, "Ordered non-wrapping combo")
		check(starts[0].clip != starts[1].clip and starts[1].clip != starts[2].clip and starts[0].clip != starts[2].clip,
			"The default phrase must visibly use three distinct authored attacks")
		check(starts[0].contact < starts[1].contact and starts[1].contact < starts[2].contact,
			"Contact cadence must progress from quick opener to weighted finisher")
	if windows.size() == 3:
		check(not windows[0].finisher and not windows[1].finisher and windows[2].finisher,
			"Only the true third hit receives finisher feedback/knockback")
	print("COMBO_CADENCE ", starts, " contacts=", contacts)
	check(is_equal_approx(hero._action_playback_speed, 1.0), "Idle must recover ordinary animation speed")
	await reset_case()
	# Hold to charge, then let the automatic hold limit release ONE blow.
	action("attack", true)
	await frames(35)
	check(hero.state_name() == "DirAttack" and attack.charging() and windows.is_empty(), "Holding preserves directional charge")
	await frames(150)
	check(starts.size() == 1 and windows.size() == 1, "Holding must never auto-chain or re-enter after recovery")
	action("attack", false)
	await reset_case()
	# Queue a follow-up, then press dodge slightly before the active frames end.
	await tap()
	await frames(6)
	await tap()
	await frames(4)
	action("dash", true)
	action("dash", false)
	var saw_dash := false
	for frame in 50:
		saw_dash = saw_dash or hero.state_name() == "Dash"
		await frames(1)
	check(saw_dash, "Early recovery dodge must be buffered until contact commitment is paid")
	check(starts.size() == 1 and windows.size() == 1, "Dodge discards the pending follow-up")
	await tap()
	await frames(60)
	check(starts.size() == 2 and starts[1].step == 0, "A new attack after dodge restarts at step zero")
	await reset_case()
	# A late dash press must rejoin DirAttack, not silently fall back to the
	# old non-directional Attack state with its different target assistance.
	action("dash", true)
	action("dash", false)
	await frames(8)
	await tap()
	var saw_directional := false
	for frame in 55:
		check(hero.state_name() != "Attack", "Dash buffer must preserve directional combat")
		saw_directional = saw_directional or hero.state_name() == "DirAttack"
		await frames(1)
	check(saw_directional and starts.size() == 1, "Late dash click starts a fresh directional opener")
	await reset_case()
	# Charging can still be cancelled into directional guard, never leaving damage.
	action("attack", true)
	await frames(10)
	var feint := InputEventMouseMotion.new()
	feint.relative = Vector2(0, -40)
	Input.parse_input_event(feint)
	await frames(3)
	check(attack.pending_dir() == SwingDir.UP and windows.is_empty(), "A held directional change still rewinds as a visible feint")
	action("block", true)
	await frames(2)
	check(hero.state_name() == "Guard" and not hitbox._active, "Guard can cancel a charge")
	action("attack", false)
	action("block", false)
	await reset_case()
	# Legacy non-input intent still owns its windup/release without human buffering.
	var enemy: CharacterBody3D = load("res://scenes/enemy_duelist.tscn").instantiate()
	enemy.get_node("DuelBrain").free()
	var brain: Node = load("res://scripts/combat/fighter_intent.gd").new()
	brain.name = "ScriptedLegacyIntent"
	enemy.add_child(brain)
	enemy.position = Vector3(25, .88, 0)
	world.add_child(enemy)
	brain.look = Vector2(0, -1)
	brain.attack_dir = SwingDir.DOWN
	brain.attack_held = true
	await frames(42)
	var enemy_attack: Node = enemy.get_node("StateMachine/DirAttack")
	check(enemy.state_name() == "DirAttack" and enemy_attack.charging(), "Legacy intent still holds its directional charge")
	check(enemy_attack.pending_dir() == SwingDir.DOWN and enemy_attack._len > .8, "Legacy telegraph/direction preserved")
	brain.attack_held = false
	brain.request_release()
	await frames(65)
	check(enemy.state_name() == "Idle", "Legacy release completes without an unsolicited combo")
	# Enemy mercy is short enough for subsequent taps; only a human gets .5 s.
	enemy.health.max_hp = 20
	enemy.health.revive()
	hitbox.set_meta("swing_dir", SwingDir.RIGHT)
	hitbox.set_meta("finisher", true)
	check(enemy.health.take_damage(1, hitbox) == 1, "First enemy damage applies")
	check(is_equal_approx(enemy.velocity.length(), 2.8), "Directional finisher gets its heavier physical shove")
	await create_timer(.12, true, false, true).timeout
	check(enemy.health.take_damage(1, hitbox) == 1, "Enemy must not swallow a valid follow-up in hero mercy frames")
	action("attack", false)
	action("block", false)
	print("DIRECTIONAL_COMBO_RESULT failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
