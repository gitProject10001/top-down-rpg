extends "res://tools/check_borgo_recipes.gd"
const Backend=preload("res://addons/npc_ai/npc_backend_llama_server.gd")
const Manifest=preload("res://addons/npc_ai/npc_package_manifest.gd")
var manager: Node
func run() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	scene.combat_encounter_enabled=false
	get_tree().root.add_child(scene); get_tree().current_scene=scene
	await settle(35)
	manager=scene.npc_dialogues
	check(manager.configured and manager.actors.size()==4,"four authored NPCs")
	var view=scene.get_node("GameplayPreviewRig/Pixel/View")
	for id in Migration.LOTS:
		await access_check(view.get_node("Borgo/Lotto_"+id))
	for actor in manager.actors:
		check(actor.grounded,actor.name+" grounded")
		var shape:=CapsuleShape3D.new(); shape.radius=.29; shape.height=1.6
		var q:=PhysicsShapeQueryParameters3D.new(); q.shape=shape; q.collision_mask=1
		q.transform.origin=actor.global_position+Vector3.UP*.85; q.exclude=[actor.get_rid(),scene.player.get_rid()]
		var obstacles: Array=actor.get_world_3d().direct_space_state.intersect_shape(q,16)
		var names:=[]
		for hit in obstacles: names.append(str(hit.collider.get_path()))
		check(obstacles.is_empty(),actor.name+" placement intersects "+str(names))
		var anchor: Node3D=actor.get_node(actor.anchor_path)
		var outward: Vector3=(actor.global_position-anchor.global_position).normalized(); outward.y=0
		scene.player.global_position=actor.global_position+outward*1.3+Vector3.UP*.1
		scene.player.velocity=Vector3.ZERO
		await settle(3)
		check(manager.find_nearest()==actor,actor.name+" reachable and visible")
		var key:=InputEventKey.new(); key.pressed=true; key.keycode=KEY_E
		Input.parse_input_event(key); Input.flush_buffered_events()
		await get_tree().process_frame
		key=key.duplicate(); key.pressed=false; Input.parse_input_event(key); Input.flush_buffered_events()
		check(manager.active==actor and get_tree().paused,actor.name+" E opens and pauses")
		if manager.active!=actor: continue
		var c: RefCounted=manager.conversations[actor.profile.npc_id]
		manager.send_text(actor.topics[0])
		await get_tree().process_frame
		check(c.state==c.State.FALLBACK,actor.name+" deterministic fallback")
		check(c.memory.npc_id==actor.profile.npc_id,"memory identity")
		var fixed_position: Vector3=scene.player.global_position
		Input.action_press("move_up")
		for i in 3: await get_tree().process_frame
		Input.action_release("move_up")
		check(scene.player.global_position.is_equal_approx(fixed_position),"movement frozen during dialogue")
		if DisplayServer.get_name()!="headless":
			for i in 35: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://captures/npc_"+str(actor.name).to_lower()+".png")
		var escape:=InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE
		Input.parse_input_event(escape); Input.flush_buffered_events()
		await get_tree().process_frame; await get_tree().process_frame
		check(not get_tree().paused and not manager.panel.visible,"close restores gameplay")
		manager.open_dialogue(actor); check(c.turn==0,"new session resets turn")
		manager.close_dialogue()
	if "--real-npcs" in OS.get_cmdline_user_args():
		var manifest:=Manifest.new(); manifest.load_from()
		var backend:=Backend.new(); backend.manifest=manifest
		manager.service.set_backend(backend)
		manager.open_dialogue(manager.actors[0]); manager.service.start()
		var started:=Time.get_ticks_msec()
		while not manager.service.is_ready() and Time.get_ticks_msec()-started<150000:
			await get_tree().process_frame
		check(manager.service.is_ready(),"real backend starts while world paused")
		print("INTEGRATED_NPC_LOAD_MS ",Time.get_ticks_msec()-started)
		if manager.service.is_ready():
			for actor in manager.actors:
				manager.open_dialogue(actor)
				var c: RefCounted=manager.conversations[actor.profile.npc_id]
				manager.send_text("Come ti chiami e di cosa ti occupi?")
				var until:=Time.get_ticks_msec()+45000
				var frames: Array[float]=[]; var last:=Time.get_ticks_usec()
				while c.state==c.State.WAITING and Time.get_ticks_msec()<until:
					await get_tree().process_frame
					var now:=Time.get_ticks_usec(); frames.append((now-last)*.001); last=now
				check(c.state==c.State.RESPONDED,actor.name+" real response")
				if c.last_response: print("INTEGRATED_NPC_REAL ",actor.name," ",c.last_response.text," timings=",c.last_response.timings)
				if DisplayServer.get_name()!="headless":
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("res://captures/npc_real_"+str(actor.name).to_lower()+".png")
				frames.sort()
				if frames.size()>5: print("INTEGRATED_NPC_FRAME_MS median=",frames[frames.size()/2]," p95=",frames[int(frames.size()*.95)])
			manager.send_text("Parlami del borgo.")
			manager.close_dialogue(); manager.open_dialogue(manager.actors[0])
			for i in 30: await get_tree().process_frame
			check(manager.conversations[manager.actors[0].profile.npc_id].turn==0,"late reply cannot enter new session")
		manager.close_dialogue()
	var packed:=PackedScene.new(); packed.pack(view.get_node("ConversationalNPCs"))
	ResourceSaver.save(packed,"user://npc_ai/test/integrated_actors.tscn")
	var restored: Node=load("user://npc_ai/test/integrated_actors.tscn").instantiate()
	check(restored.get_child_count()==4,"four actors roundtrip")
	for actor in restored.get_children():
		check(actor.profile.is_valid() and not actor.anchor_path.is_empty(),"profile and anchor roundtrip")
	restored.free()
	print("INTEGRATED_NPC_RESULT failures=",failures)
	scene.queue_free(); await get_tree().process_frame; await get_tree().process_frame
	get_tree().call_deferred("quit",0 if failures.is_empty() else 1)
