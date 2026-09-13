extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/castle_interiors_example.tscn").instantiate()
	var group=example.get_node("Castello"); example.remove_child(group); own(group,group)
	var packed := PackedScene.new(); assert(packed.pack(group)==OK); group.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	await play._walk(Vector3(8,0,2.6),120)
	var gate=play.nearest_door(); assert(gate!=null); gate.toggle(play.player.global_position)
	for i in 45: await physics_frame
	await play._walk(Vector3(8,0,-8),400)
	for name in ["TorreEst","TorreNordEst","TorreNordOvest","TorreOvest"]:
		var tower=play.authored_group.get_node(name)
		var opening: Dictionary=tower.resolved_opening(tower.openings[0])
		var outer: Vector3=tower.wall_point(opening.wall,opening.along,0,1.1)
		var inner: Vector3=tower.wall_point(opening.wall,opening.along,0,-1.0)
		var side: float=0.9 if inner.x>0 else -0.9
		await play._walk(tower.to_global(outer),400)
		var door=play.nearest_door(); assert(door==tower._generated.get_node("Door_0"),"Nearest door belongs to approached tower")
		door.toggle(play.player.global_position); for i in 45: await physics_frame
		await play._walk(tower.to_global(inner),160)
		assert(play.inside and play.house==tower and play.active_floor==0,"Correct interior on entering "+name)
		assert(play.lamps[0].global_position.distance_to(tower.to_global(Vector3(-2,2,-2.5)))<0.01)
		await play._walk(tower.to_global(Vector3(inner.x,0,minf(inner.z,1.6))),120)
		await play._walk(tower.to_global(Vector3(side,0,minf(inner.z,1.6))),120)
		await play._walk(tower.to_global(Vector3(side,0,3.1)),200)
		await play._walk(tower.to_global(Vector3(0,0,3.1)),120)
		await play._walk(tower.to_global(Vector3(0,2.85,-2.65)),400)
		print("ASCENT_STATE ",name," local=",tower.to_local(play.player.global_position)," active=",play.house.name," floor=",play.active_floor," inside=",play.inside)
		assert(play.inside and play.active_floor==1 and play.authored_plan==tower.get_node("InteriorPlan"))
		if DisplayServer.get_name()!="headless" and name=="TorreNordEst":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/balcony_attachment/castle_secondary_interior_play.png")
		await play._walk(tower.to_global(Vector3(1.5,2.85,-2.65)),160)
		await play._walk(tower.to_global(Vector3(1.5,5.78,2.65)),450)
		assert(not play.inside and tower._generated.get_node("Roof").visible,"Roof restores exterior")
		await play._walk(tower.to_global(Vector3(1.5,2.85,-2.65)),450)
		assert(play.inside and play.active_floor==1)
		await play._walk(tower.to_global(Vector3(0,2.85,-2.65)),160)
		await play._walk(tower.to_global(Vector3(0,0,2.65)),400)
		await play._walk(tower.to_global(Vector3(side,0,2.65)),120)
		await play._walk(tower.to_global(Vector3(side,0,minf(inner.z,1.6))),200)
		await play._walk(tower.to_global(Vector3(inner.x,0,minf(inner.z,1.6))),120)
		await play._walk(tower.to_global(inner),120)
		await play._walk(tower.to_global(outer),160)
		assert(not play.inside and tower._generated.get_node("Roof").visible)
		await play._walk(Vector3(8,0,-8),400)
		print("TOWER_INTERIOR_ROUTE_OK ",name)
	print("CASTLE_ALL_TOWER_INTERIORS_ROOFS_LIGHTS_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
