extends Node
## Actual integrated encounter, repeatable input, death ownership and reset.
var failures: PackedStringArray=[]
var player_deaths:=0
var enemy_deaths:=0
var hits_taken:=0
var scene: Node3D

func _ready() -> void:
	Engine.max_fps=60
	call_deferred("run")

func check(value: bool,message: String) -> void:
	if not value: failures.append(message); push_error("MEADOW_ENCOUNTER: "+message)

func settle(frames: int) -> void:
	for i in frames: await get_tree().physics_frame

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.pressed=true
	scene._unhandled_key_input(event)

func run() -> void:
	var bus:=get_tree().root.get_node("EventBus")
	bus.player_died.connect(func(): player_deaths+=1)
	bus.enemy_died.connect(func(_enemy): enemy_deaths+=1)
	scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	if not "--full" in OS.get_cmdline_user_args():
		# Keep actual terrain, forest and water for ground placement/avoidance.
		for child in scene.get_children():
			if child.name not in ["TerrenoComposto","Boschi","ArtStudyLayers"] and not child.has_method("contains_point"):
				child.free()
	get_tree().root.add_child(scene)
	get_tree().current_scene=scene
	await settle(60)
	var encounter=scene.combat_encounter
	check(encounter!=null,"Default integrated scene must contain combat")
	if encounter==null: get_tree().quit(1); return
	var player: Player=scene.player
	player.health.damaged.connect(func(_amount,_source): hits_taken+=1)
	check(encounter.living_count()==4,"Expected four alive raiders")
	for enemy in encounter.fighters:
		check(enemy.health.max_hp==4 and enemy.is_in_group("enemy") and not enemy.is_in_group("player"),"Raider health/team is incorrect")
		check(enemy.has_meta("hearth_warden_applied"),"Raider needs its distinct in-world costume")
		check(enemy.has_node("CombatMarker/HealthPips") and enemy.has_node("CombatMarker/AttackTell"),"Missing visible health/windup cues")
	key(KEY_4)
	await settle(65)
	check(encounter.living_count()==4 and player.global_position.distance_to(encounter.arena_center)<10,"4 must reset and enter the real meadow encounter")
	player.health.max_hp=100
	player.health.revive()
	var starts:=PackedVector3Array()
	var travelled:=PackedFloat32Array()
	for enemy in encounter.fighters: starts.append(enemy.global_position)
	travelled.resize(encounter.fighters.size())
	print("MEADOW_START player=",player.global_position," enemies=",starts)
	for frame in 660:
		await get_tree().physics_frame
		check(encounter.director.snapshot().holders<=2,"Too many simultaneous attack turns")
		for index in encounter.fighters.size():
			travelled[index]=maxf(travelled[index],encounter.fighters[index].global_position.distance_to(starts[index]))
		if "--trace" in OS.get_cmdline_user_args() and frame%120==0:
			for enemy in encounter.fighters:
				print("MEADOW_TRACE ",frame," ",enemy.name," pos=",enemy.global_position," state=",enemy.state_name()," move=",enemy.intent.move," safe=",encounter.director.safe_step(enemy,Vector2(0,1))," can_attack=",encounter.director.can_attack(enemy))
	print("MEADOW_TURNS ",encounter.director.snapshot())
	var moved:=0
	for i in encounter.fighters.size():
		if travelled[i]>.6: moved+=1
	for turns in encounter.director.snapshot().turns.values():
		check(turns>0,"Every member of the group must receive a turn")
	check(moved>=3,"Pack must approach and occupy different positions")
	check(hits_taken>0,"Actual enemy sword attacks never damaged the player")
	var combat_hits:=hits_taken
	var before:=player_deaths
	for enemy in encounter.fighters:
		enemy.health.take_damage(20,player.sword.get_node("HitBox"))
	await settle(3)
	check(player_deaths==before,"Killing an enemy emitted player_died")
	check(enemy_deaths==4 and encounter.living_count()==0,"Enemy deaths must be counted once")
	for enemy in encounter.fighters:
		if is_instance_valid(enemy): check(enemy.collision_layer==0,"Dead enemy blocks the encounter")
	player.health.revive() # Clear a last enemy hit's mercy window before this fixture.
	player.health.take_damage(1000)
	await settle(1)
	check(not player.health.is_alive(),"Death fixture must kill the hero")
	player.health.max_hp=5
	key(KEY_R)
	await settle(70)
	check(player.health.is_alive() and player.state_name()!="Dead","R must revive the hero")
	check(encounter.living_count()==4,"R must restore four enemies without leftovers")
	if DisplayServer.get_name()!="headless":
		var viewport: SubViewport=player.get_viewport()
		viewport.get_parent().stretch=false
		viewport.size=Vector2i(1152,648)
		player.health.invulnerable=true
		# The headless fixture's sleep limiter adds latency on top of VSync.
		# Measure the scene with the normal project's uncapped setting.
		Engine.max_fps=0
		await settle(120)
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
		var gpu_ms: Array[float]=[]
		var frame_ms: Array[float]=[]
		var before_frame:=Time.get_ticks_usec()
		for sample in 120:
			await RenderingServer.frame_post_draw
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
			var now:=Time.get_ticks_usec()
			frame_ms.append((now-before_frame)*.001)
			before_frame=now
		gpu_ms.sort()
		frame_ms.sort()
		print("MEADOW_PERFORMANCE viewport=1152x648 frames=120 gpu_median_ms=",gpu_ms[60]," gpu_p95_ms=",gpu_ms[114]," frame_median_ms=",frame_ms[60]," frame_p95_ms=",frame_ms[114])
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://captures/meadow_group_combat.png")
	print("MEADOW_ENCOUNTER_RESULT combat_hits=",combat_hits," moved=",moved," enemy_deaths=",enemy_deaths," player_deaths=",player_deaths," failures=",failures)
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit",0 if failures.is_empty() else 1)
