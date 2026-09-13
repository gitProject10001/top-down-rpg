extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/roof_door_example.tscn").instantiate()
	var house=example.get_node("CasaComposta"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var terrace=play.house.authored_volumes()[0]
	var bottom: Vector3=terrace.to_global(terrace.stair_frame()*Vector3(0,terrace.stair_ground()-terrace.effective_elevation(),terrace.stair_run()+0.7))
	var landing: Vector3=terrace.to_global(terrace.stair_frame()*Vector3(0,0,-0.7))
	await play._walk(Vector3(-1.05,0,6),120)
	await play._walk(Vector3(bottom.x,0,6),600)
	await play._walk(bottom,400)
	await play._walk(landing,500)
	var collision: CollisionShape3D=play.player.get_node("Collision")
	var feet: float=play.player.position.y+collision.position.y-collision.shape.height*0.5
	assert(feet>terrace.effective_elevation()-0.15,"Player climbs through parapet gap")
	assert(not play.inside and terrace._generated.get_node("Roof").visible,"Roof is outdoors and remains visible")
	await play._walk(terrace.to_global(Vector3(0,terrace.effective_elevation(),0)),220)
	assert(not play.inside)
	var door_point: Vector3=play.house.wall_point(terrace.host_wall,terrace.host_offset*play.house.wall_length(terrace.host_wall)*0.5,terrace.effective_elevation(),0.7)
	await play._walk(door_point,180)
	var door=play.nearest_door(); assert(door!=null and door.toggle(play.player.global_position))
	for i in 30: await physics_frame
	var inner: Vector3=door_point-play.house.wall_normal(terrace.host_wall)*1.5
	await play._walk(inner,220)
	assert(play.inside and play.active_floor==1,"Door enters actual upper floor")
	feet=play.player.position.y+collision.position.y-collision.shape.height*0.5
	assert(feet>terrace.effective_elevation()-0.1,"Interior slab supports the player")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/roof_door_play.png")
	await play._walk(door_point,220); assert(not play.inside,"Return to roof restores outside")
	await play._walk(landing,220)
	await play._walk(bottom,500)
	feet=play.player.position.y+collision.position.y-collision.shape.height*0.5
	assert(feet<0.15,"Player descends to ground")
	print("ROOF_DOOR_REAL_PLAYER_UPPER_FLOOR_RETURN_DESCEND_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()
