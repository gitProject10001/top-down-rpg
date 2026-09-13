extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/tower_interior_example.tscn").instantiate()
	var house=example.get_node("TorreOttagonale"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var door=play.house._generated.get_node("Door_0"); assert(door.toggle(play.player.global_position))
	for i in 45: await physics_frame
	await play._walk(Vector3(0,0,2.6),200)
	assert(play.inside,"Entering polygon tower activates interior view")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/tower_interior_ground_play.png")
	await play._walk(Vector3(0,2.85,-2.5),400)
	var shape: CollisionShape3D=play.player.get_node("Collision")
	var feet: float=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(feet>2.7 and play.active_floor==1,"Player reaches authored upper floor through stair opening")
	await play._walk(Vector3(1.3,2.85,-2.3),120)
	assert(play.inside and play.active_floor==1)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/tower_interior_upper_play.png")
	await play._walk(Vector3(0,2.85,-2.5),120)
	await play._walk(Vector3(0,0,2.6),400)
	feet=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(feet<0.15 and play.active_floor==0,"Player descends without falling through floor")
	await play._walk(Vector3(0,0,4.0),180); assert(not play.inside)
	print("TOWER_INTERIOR_REAL_PLAYER_ENTER_ASCEND_DESCEND_EXIT_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
