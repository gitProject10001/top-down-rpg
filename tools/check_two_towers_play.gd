extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/two_towers_example.tscn").instantiate()
	var house=example.get_node("Fortificazione"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var door=play.house._generated.get_node("Door_0"); assert(door.toggle(play.player.global_position))
	for i in 45: await physics_frame
	await play._walk(Vector3(0,0,2.6),200)
	assert(play.inside,"Entering polygon tower activates interior view")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/tower_roof_stair_ground.png")
	await play._walk(Vector3(0,2.85,-2.5),400)
	var shape: CollisionShape3D=play.player.get_node("Collision")
	var feet: float=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(feet>2.7 and play.active_floor==1,"Player reaches authored upper floor through stair opening")
	await play._walk(Vector3(1.3,2.85,-2.3),120)
	assert(play.inside and play.active_floor==1)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/tower_roof_stair_upper.png")
	await play._walk(Vector3(1.5,2.85,-2.65),120)
	await play._walk(Vector3(1.5,5.78,2.65),450)
	feet=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(feet>5.65 and not play.inside,"Player reaches roof from interior")
	assert(play.house._generated.get_node("Roof").visible,"Roof visible outdoors")
	assert(play.authored_plan.get_node("PrimoPiano/ScalaTetto").is_visible_in_tree(),"Roof stair remains visible for descent")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/tower_roof_stair_play.png")
	await play._walk(Vector3(3,5.78,2.65),120)
	await play._walk(Vector3(3,5.78,0),150)
	await play._walk(Vector3(16,5.78,0),350)
	feet=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(play.player.position.x>15.5 and feet>5.65 and not play.inside,"Player crosses tower parapet and curtain end without falling")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/two_towers_play.png")
	await play._walk(Vector3(3,5.78,0),350)
	await play._walk(Vector3(3,5.78,2.65),150)
	await play._walk(Vector3(1.5,5.78,2.65),120)
	await play._walk(Vector3(1.5,2.85,-2.65),450)
	assert(play.inside and play.active_floor==1,"Descent restores upper interior")
	await play._walk(Vector3(0,2.85,-2.5),120)
	await play._walk(Vector3(0,0,2.6),400)
	feet=play.player.position.y+shape.position.y-shape.shape.height*0.5
	assert(feet<0.15 and play.active_floor==0,"Player descends without falling through floor")
	await play._walk(Vector3(0,0,4.0),180); assert(not play.inside)
	print("TWO_TOWERS_REAL_PLAYER_ROUNDTRIP_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
