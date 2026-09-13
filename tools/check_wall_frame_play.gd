extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/wall_frame_example.tscn").instantiate()
	var house=example.get_node("CasaComposta"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	assert(not play.inside,"Under the porch is outdoors")
	await play._walk(Vector3(-1.05,0,4.7),120); assert(not play.inside)
	var entry=play.nearest_door(); assert(entry!=null and entry.toggle(play.player.global_position))
	for i in 30: await physics_frame
	await play._walk(Vector3(-1.05,0,2.8),180); assert(play.inside)
	await play._walk(Vector3(-1.05,0,7.8),250); assert(not play.inside and play.player.position.z>7)
	await play._walk(Vector3(6,0,7.8),300)
	await play._walk(Vector3(6,0,-1.4),350)
	assert(not play.inside and play.player.position.z<0,"Freestanding canopy is traversable and outdoors")
	print("PORCH_REAL_PLAYER_ENTER_EXIT_CANOPY_OUTDOORS_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()
