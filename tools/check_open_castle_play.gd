extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/castle_open_courtyard_example.tscn").instantiate()
	var group=example.get_node("CastelloAperto"); example.remove_child(group); own(group,group)
	var packed := PackedScene.new(); assert(packed.pack(group)==OK); group.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	print(play.authored_group.diagnostics())
	assert(play.authored_group.diagnostics().is_empty())
	await play._walk(Vector3(13,0,2.6),100)
	var gate=play.nearest_door(); assert(gate!=null); gate.toggle(play.player.global_position)
	for i in 45: await physics_frame
	await play._walk(Vector3(13,0,-3),250)
	await play._walk(Vector3(19,0,-3),220)
	var visibility=play.view.get_node("World/ArchitectureVisibility")
	for enabled in [false,true]:
		play.authored_group.courtyard_visibility=enabled
		for i in 120: await physics_frame
		assert(visibility._radius>3.5 if enabled else is_zero_approx(visibility._radius))
		if enabled:
			assert(visibility.sections.solid_sections>0,"Solid walls need stone cross sections")
			assert(visibility.sections.hollow_sections>0,"Hollow towers need dark shell cross sections")
			print("SECTION_COUNTS ",visibility.sections.solid_sections," / ",visibility.sections.hollow_sections," build_usec=",visibility.sections.last_build_usec)
		else:
			assert(visibility.sections.solid_sections==0 and visibility.sections.hollow_sections==0)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/balcony_attachment/open_castle_%s.png"%("revealed" if enabled else "occluded"))
	var space=play.player.get_world_3d().direct_space_state
	var query=PhysicsRayQueryParameters3D.create(Vector3(19,1,2),Vector3(19,1,-2))
	assert(not space.intersect_ray(query).is_empty(),"Visual cut preserves wall collision")
	await play._walk(Vector3(19,0,-10),220)
	assert(not play.inside and play.player.position.z<-9.5)
	for i in 90: await physics_frame
	assert(not visibility.occluded and is_zero_approx(visibility._radius),"Visible player must restore the complete walls")
	assert(visibility.sections.solid_sections==0 and visibility.sections.hollow_sections==0)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/open_castle_visible_uncut.png")
	print("VISIBLE_PLAYER_NO_REVEAL_OK")
	await play._walk(Vector3(19,0,-3),220)
	for i in 45: await physics_frame
	assert(visibility.occluded and visibility._radius>3.5,"Returning behind walls must reactivate the reveal")
	# On the walkway the reveal threshold stays above the player's feet.
	play.player.position=Vector3(13,6.7,0); play.player.velocity=Vector3.ZERO
	for i in 40: await physics_frame
	assert(play.player.position.y>6.5 and not play.inside)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/balcony_attachment/open_castle_walkway.png")
	print("OPEN_CASTLE_REVEAL_RESTORE_COLLISION_WALKWAY_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
