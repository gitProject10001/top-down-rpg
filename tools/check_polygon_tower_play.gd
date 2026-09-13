extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/polygon_tower_example.tscn").instantiate()
	var house=example.get_node("TorreOttagonale"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var terrace=play.house
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
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/polygon_tower_play.png")
	await play._walk(landing,220)
	await play._walk(bottom,500)
	feet=play.player.position.y+collision.position.y-collision.shape.height*0.5
	assert(feet<0.15,"Player descends to ground")
	print("POLYGON_TOWER_REAL_PLAYER_ASCEND_OUTDOORS_DESCEND_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()
