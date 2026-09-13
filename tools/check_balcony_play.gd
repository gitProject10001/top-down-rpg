extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/balcony_attachment_example.tscn").instantiate()
	var house=example.get_node("CasaConBalcone"); example.remove_child(house); own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK); house.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var entry=play.nearest_door(); assert(entry!=null); assert(entry.toggle(play.player.global_position))
	for i in 30: await physics_frame
	await play._walk(Vector3(-1.5,0,2.6),150); assert(play.inside)
	await play._walk(Vector3(-1.6,2.8,-2.6),300); assert(play.active_floor==1,"Player climbs to balcony floor")
	await play._walk(Vector3(0,2.8,-2.6),150)
	await play._walk(Vector3(0,2.8,2.8),300)
	await play._walk(Vector3(0,2.8,4.2),150)
	assert(play.player.position.z>3.7 and play.player.position.y>2.5,"Real player crosses onto balcony")
	await play._walk(Vector3(0,2.8,2.7),150); assert(play.inside,"Player returns through balcony door")
	print("BALCONY_REAL_PLAYER_STAIRS_EXIT_RETURN_OK")
	play.queue_free()
	for i in 3: await process_frame
	quit()
