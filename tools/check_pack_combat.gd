extends Node
## Run as a scene so the real shared combat autoloads are registered before Player compiles:
## godot --headless --path . res://tools/check_pack_combat.tscn
const Director = preload("res://scripts/combat/pack_director.gd")
const Raider = preload("res://scenes/enemy_raider.tscn")
const Hero = preload("res://scenes/player/player3.tscn")
var failures := 0
var world: Node3D
var damage_events := 0

class WaterPatch extends Node3D:
	func contains_point(point: Vector2) -> bool: return point.x > .2 and point.x < 2
	func set_simulation(_on: bool) -> void: pass

func _ready() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("PACK_COMBAT: " + label)

func frames(count: int) -> void:
	for _i in count: await get_tree().physics_frame

func actor_at(label: String, point: Vector3) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.name = label
	actor.position = point
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.4
	shape.shape = capsule
	actor.add_child(shape)
	var health := Health.new()
	health.name = "Health"
	actor.add_child(health)
	world.add_child(actor)
	return actor

func box(label: String, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = point
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func run() -> void:
	world = Node3D.new()
	add_child(world)
	box("Floor", Vector3(0, -.25, 0), Vector3(20, .5, 20))
	var target := actor_at("Target", Vector3(0, .71, 0))
	var director := Director.new()
	world.add_child(director)
	director.configure(target, Vector3.ZERO)
	director.set_physics_process(false)
	var pack: Array[CharacterBody3D] = []
	for i in 4:
		var angle := float(i) * TAU / 4
		pack.append(actor_at("Raider%d" % i, Vector3(cos(angle) * 2.7, .71, sin(angle) * 2.7)))
	await frames(3)
	for actor in pack:
		director.report(actor, true, false)
		director.request_turn(actor)
	check(director.snapshot().holders == 2, "initial leases reach the two-turn cap")
	check(director.begin_attack(pack[0]), "first holder begins")
	check(not director.begin_attack(pack[1]), "second cannot start simultaneously")
	for actor in pack: director.report(actor, true, actor == pack[0])
	director._physics_process(.20)
	check(not director.begin_attack(pack[1]), "start spacing lasts beyond .20s")
	for actor in pack: director.report(actor, true, actor == pack[0])
	director._physics_process(.11)
	check(director.begin_attack(pack[1]), "second begins after .30s")
	director.release_turn(pack[0])
	director.report(pack[0], false, false, true)
	director._physics_process(.01)
	check(director.holds_turn(pack[2]), "waiting third actor receives a freed turn")
	director.release_turn(pack[1])
	director.report(pack[1], false, false, true)
	director._physics_process(.01)
	check(director.holds_turn(pack[3]), "waiting fourth actor receives next turn")
	check(director.snapshot().holders == 2, "fair rotation preserves cap")
	pack[2].get_node("Health").take_damage(100)
	director._physics_process(.01)
	check(not director.holds_turn(pack[2]), "death releases lease even without a brain report")
	pack[3].queue_free()
	await frames(2)
	check(director.snapshot().holders == 0, "despawn releases lease")
	pack[1].position = pack[0].position + Vector3(.45, 0, 0)
	var away: Vector2 = director.separation_for(pack[0])
	check(away.x < -.1, "neighbor repulsion points away from a nearby actor")
	var station: Vector3 = director.station_for(pack[0])
	check(absf(Vector2(station.x, station.z).length() - director.ring_radius) < .01, "waiting station lies on combat ring")
	pack[0].position = Vector3(-2, .71, 0)
	var wall := box("Wall", Vector3(-1, 1, 0), Vector3(.25, 2, 3))
	await frames(2)
	check(not director.can_attack(pack[0]), "wall denies attack lane")
	wall.queue_free()
	await frames(2)
	check(director.can_attack(pack[0]), "clear lane permits attack")
	target.position.y = 3
	check(not director.can_attack(pack[0]), "different elevation denies attack")
	target.position.y = .71
	pack[0].position = Vector3(9.7, .71, 0)
	check(not director.safe_step(pack[0], Vector2.RIGHT), "floor lookahead rejects ledge")
	pack[0].position = Vector3(0, .71, 3)
	check(director.safe_step(pack[0], Vector2.RIGHT), "clear floor accepts movement")
	var water := WaterPatch.new()
	world.add_child(water)
	director.water_bodies.append(water)
	check(not director.safe_step(pack[0], Vector2.RIGHT), "local water boundary rejects movement")
	director.queue_free()
	for actor in pack:
		if is_instance_valid(actor): actor.queue_free()
	target.queue_free()
	water.queue_free()
	await frames(2)
	await real_combo()
	await death_physics()
	await action_controls()
	await live_pack()
	print("PACK_COMBAT_CHECK failures=", failures, " damage_events=", damage_events)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

func real_combo() -> void:
	var hero := Hero.instantiate() as Player
	hero.name = "ComboHero"
	hero.position = Vector3(0, 1, 0)
	world.add_child(hero)
	check(hero.max_stamina == 180.0 and hero.stamina == 180.0, "hero spawns with the full larger reserve")
	check(not hero.has_node("StateMachine/DirAttack"), "human uses action combo, no directional attack state")
	hero.intent.set_physics_process(false)
	hero.intent.clear()
	hero.intent.look = Vector2(0, -1)
	var receiver := Raider.instantiate() as Player
	receiver.name = "ComboRaider"
	receiver.position = Vector3(0, 1, -1.15)
	receiver.get_node("Health").max_hp = 20
	world.add_child(receiver)
	receiver.intent.set_physics_process(false)
	receiver.intent.clear()
	await frames(25)
	var attack := hero.get_node("StateMachine/Attack")
	var contacts: Array[int] = []
	var windows: Array[int] = []
	receiver.health.damaged.connect(func(_amount: int, _source: Node) -> void: contacts.append(attack.combo_index()))
	attack.damage_window_opened.connect(func(index: int, _duration: float) -> void:
		windows.append(index)
		if index < 2:
			hero.intent._sample_attack_button(true)
			hero.intent._sample_attack_button(false))
	hero.intent._sample_attack_button(true)
	hero.intent._sample_attack_button(false)
	await frames(100)
	check(windows == [0, 1, 2], "real human body opens exactly three buffered combo windows")
	check(contacts == [0, 1, 2], "all three action combo strokes contact the real raider capsule")
	print("PACK_REAL_COMBO windows=", windows, " contacts=", contacts,
		" hero=", hero.global_position, " raider=", receiver.global_position, " hp=", receiver.health.hp)
	hero.queue_free()
	receiver.queue_free()
	await frames(3)

func live_pack() -> void:
	var hero := Hero.instantiate() as Player
	hero.name = "Hero"
	hero.position = Vector3(0, 1, 0)
	hero.get_node("Health").max_hp = 100
	world.add_child(hero)
	# Keep the shared character, FSM, animation, sword and hurtbox; disable only human input.
	hero.intent.set_physics_process(false)
	hero.intent.clear()
	hero.health.damaged.connect(func(_amount: int, _source: Node) -> void: damage_events += 1)
	var director := Director.new()
	world.add_child(director)
	director.configure(hero, Vector3.ZERO)
	var raiders: Array[Player] = []
	for i in 4:
		var raider := Raider.instantiate() as Player
		raider.name = "Bandit%d" % i
		raider.position = Vector3(cos(float(i) * TAU / 4) * 3.5, 1, sin(float(i) * TAU / 4) * 3.5)
		raider.get_node("DuelBrain").brain_seed = i + 11
		world.add_child(raider)
		raider.get_node("DuelBrain").configure(director, hero)
		raiders.append(raider)
		check(raider.health.max_hp == 4 and not raider.is_input_driven(), "raider inherits shared body with HP4 and AI intent")
		check(is_equal_approx(raider.intent.engage_range, 9.0) and is_equal_approx(raider.intent.guard_read, .20), "raider scene overrides inherited duelist range and guard defaults")
	var maximum := 0
	var max_committed := 0
	for tick in 960:
		await get_tree().physics_frame
		maximum = maxi(maximum, director.snapshot().holders)
		var committed := 0
		for raider in raiders:
			if raider.state_name() == "DirAttack": committed += 1
		max_committed = maxi(max_committed, committed)
	check(maximum == 2 and max_committed <= 2, "real bodies obey two simultaneous attack slots")
	check(damage_events >= 2, "real pack lands repeated physical sword damage")
	var stats: Dictionary = director.snapshot()
	for actor_name in stats.turns:
		check(stats.turns[actor_name] >= 1, "every real pack member gets an attacking turn: " + actor_name)
	print("PACK_LIVE ", stats, " max_committed=", max_committed, " hero_hp=", hero.health.hp)
	var dialogue := get_tree().root.get_node("Dialogue")
	dialogue.active = true
	await frames(3)
	check(director.snapshot().holders == 0, "dialogue releases all attack turns")
	for raider in raiders:
		check(not raider.intent.attack_held and raider.intent.move == Vector2.ZERO, "dialogue clears pack intents")
	dialogue.active = false
	await frames(60)
	check(director.snapshot().holders > 0, "pack resumes active turns after dialogue")
	hero.health.revive() # Remove any real hit's temporary i-frames before the lethal fixture.
	hero.health.take_damage(1000)
	await frames(3)
	check(not hero.health.is_alive(), "target death fixture really kills the hero")
	check(director.snapshot().holders == 0, "target death clears all attack turns")
	for raider in raiders: raider.queue_free()
	hero.queue_free()
	director.queue_free()

func death_physics() -> void:
	var enemy := Raider.instantiate() as Player
	enemy.position = Vector3(3, 1, 0)
	world.add_child(enemy)
	enemy.intent.set_physics_process(false)
	await frames(20)
	var rag := enemy.find_child("Ragdoll", true, false) as PhysicalBoneSimulator3D
	check(rag != null and rag.get_child_count() == 18, "raider inherits eighteen authored physical bones")
	check(not rag.is_simulating_physics(), "living enemy has no active corpse simulation")
	var origin := enemy.global_position
	var source := Node3D.new()
	world.add_child(source)
	source.global_position = origin + Vector3.FORWARD
	source.set_meta("finisher", true)
	enemy.health.take_damage(100, source)
	await frames(4)
	check(rag.is_simulating_physics(), "lethal blow starts physical ragdoll")
	check(not enemy._tree.active and not enemy._fsm.is_physics_processing(), "corpse has no competing animation or movement")
	check(not enemy.sword.get_node("HitBox")._active, "death closes sword damage window")
	check(enemy.collision_layer == 0, "corpse releases character collision")
	await frames(150)
	var hips := rag.get_node("pb_Hips") as PhysicalBone3D
	check(hips.global_position.is_finite() and hips.global_position.distance_to(origin) < 5, "ragdoll settles locally without exploding")
	check(hips.global_position.y > -.15 and hips.global_position.y < .8, "corpse falls onto the floor rather than standing or tunneling")
	print("PACK_RAGDOLL hips=", hips.global_position, " velocity=", hips.linear_velocity)
	enemy.queue_free()
	source.queue_free()
	await frames(2)

func action_controls() -> void:
	var hero := Hero.instantiate() as Player
	hero.position = Vector3(0,1,0)
	world.add_child(hero)
	hero.intent.set_physics_process(false)
	await frames(20)
	var attack := hero.get_node("StateMachine/Attack")
	var starts: Array[int] = []
	attack.combo_step_started.connect(func(index: int, _dir: int, _clip: String): starts.append(index))
	hero.intent._sample_attack_button(true)
	await frames(80)
	check(starts == [0], "holding click produces one action swing, no charge or automatic combo")
	hero.intent._sample_attack_button(false)
	await frames(2)
	hero.intent._sample_attack_button(true)
	hero.intent._sample_attack_button(false)
	await frames(3)
	var dodge := InputEventAction.new()
	dodge.action = "dash"
	dodge.pressed = true
	attack.handle_input(dodge)
	var dodged := false
	for i in 18:
		await frames(1)
		if hero.state_name() == "Dash": dodged = true
	check(dodged, "early dodge input is buffered until sword contact")
	await frames(50)
	hero.intent.guard = true
	hero.get_node("StateMachine").transition_to("Guard")
	await frames(14)
	var guard := hero.get_node("StateMachine/Guard")
	for direction in SwingDir.ALL:
		check(guard.blocks(direction), "frontal guard accepts any cut direction")
	hero.intent.guard = false
	hero.get_node("StateMachine").transition_to("Idle")
	hero.stamina = 100.0
	hero._update_resources(1.0)
	check(is_equal_approx(hero.stamina,130.0), "one second recovers thirty stamina outside guard")
	hero.queue_free()
	await frames(2)
