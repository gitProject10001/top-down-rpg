extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node, scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/castle_keep_accessory_example.tscn").instantiate()
	var group=example.get_node("Castello"); example.remove_child(group); own(group,group)
	assert(group.towers().size()==4 and group.buildings().size()==5)
	var packed := PackedScene.new(); assert(packed.pack(group)==OK); group.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	var keep=play.authored_group.get_node("Mastio")
	assert(play.authored_group.diagnostics().is_empty(),"Keep must not become a curtain vertex")
	await play._walk(Vector3(8,0,2.6),120)
	var gate=play.nearest_door(); assert(gate!=null); gate.toggle(play.player.global_position)
	for i in 45: await physics_frame
	await play._walk(Vector3(8,0,-4),300)
	var door=play.nearest_door(); assert(door==keep._generated.get_node("Door_0")); door.toggle(play.player.global_position)
	for i in 45: await physics_frame
	await play._walk(keep.to_global(Vector3(0,0,1.1)),150)
	assert(play.inside and play.house==keep and play.active_floor==0)
	var accessory=keep.get_node("Volumes/CorpoAccessorio")
	assert(accessory.volume_error().is_empty())
	await play._walk(keep.to_global(Vector3(-2,0,0)),160)
	var passage=play.nearest_door(); assert(passage!=null and passage!=door)
	await play._walk(keep.to_global(Vector3(-4.2,0,0)),100)
	assert(keep.to_local(play.player.global_position).x>-3,"Closed junction door blocks passage")
	passage.toggle(play.player.global_position); for i in 45: await physics_frame
	await play._walk(keep.to_global(Vector3(-4.2,0,0)),180)
	assert(keep.to_local(play.player.global_position).x<-3.7)
	assert(play.inside and play.house==keep and play.active_floor==0 and not accessory._generated.get_node("Roof").visible)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/keep_accessory_play.png")
	await play._walk(keep.to_global(Vector3(0,0,0)),180)
	await play._walk(keep.to_global(Vector3(0,0,1.1)),100)
	print("KEEP_ACCESSORY_DOOR_COLLISION_ENTER_RETURN_OK")
	await play._walk(keep.to_global(Vector3(0,0,2.4)),100)
	await play._walk(keep.to_global(Vector3(1.2,0,2.4)),100)
	await play._walk(keep.to_global(Vector3(1.2,2.85,-2.4)),350)
	print("KEEP_FLOOR1 ",keep.to_local(play.player.global_position))
	assert(play.inside and play.active_floor==1)
	await play._walk(keep.to_global(Vector3(-1.2,2.85,-2.4)),140)
	await play._walk(keep.to_global(Vector3(-1.2,5.65,2.4)),350)
	print("KEEP_FLOOR2 ",keep.to_local(play.player.global_position))
	assert(play.inside and play.active_floor==2 and play.storeys==3)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/keep_interior_play.png")
	await play._walk(keep.to_global(Vector3(-1.2,2.85,-2.4)),350)
	assert(play.active_floor==1)
	await play._walk(keep.to_global(Vector3(1.2,2.85,-2.4)),140)
	await play._walk(keep.to_global(Vector3(1.2,0,2.4)),350)
	await play._walk(keep.to_global(Vector3(0,0,2.4)),100)
	await play._walk(keep.to_global(Vector3(0,0,1.1)),100)
	await play._walk(Vector3(8,0,-4),200)
	assert(not play.inside and keep._generated.get_node("Roof").visible)
	print("KEEP_THREE_FLOORS_ENTER_ASCEND_DESCEND_EXIT_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
