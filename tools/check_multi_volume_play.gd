extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/multi_volume_example.tscn").instantiate()
	var house=example.get_node("CasaComposta"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var entry=play.nearest_door(); assert(entry!=null); assert(entry.toggle(play.player.global_position))
	for i in 30: await physics_frame
	await play._walk(Vector3(-1.05,0,2.8),180); assert(play.inside)
	await play._walk(Vector3(1.7,0,-2.0),250)
	await play._walk(Vector3(5.5,0,-2.0),250)
	assert(play.player.position.x>4.6 and play.inside,"Player crosses main/annex junction and remains indoors")
	assert(not play.house.authored_volumes()[0]._generated.get_node("Roof").visible)
	await play._walk(Vector3(1.5,0,-2.0),250); assert(play.player.position.x<2)
	print("MULTI_VOLUME_REAL_PLAYER_JUNCTION_RETURN_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()
