extends SceneTree
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	for child in node.get_children(): child.owner=scene; own(child,scene)
func run() -> void:
	var example=load("res://scenes/dev/castle_sloped_walkways_example.tscn").instantiate()
	var group=example.get_node("Castello"); example.remove_child(group); own(group,group)
	var packed := PackedScene.new(); assert(packed.pack(group)==OK); group.free(); example.free()
	var play=load("res://scripts/village/house_interior_play.gd").new(); play.authored_house_scene=packed; root.add_child(play)
	for i in 30: await physics_frame
	assert(play.authored_group.diagnostics().is_empty())
	# Isolate the walkway regression: spawn on the first roof, then use real movement/collision.
	for x in [0.0,16.0]:
		play.player.global_position=Vector3(x,6.7,0); play.player.velocity=Vector3.ZERO
		for i in 30: await physics_frame
		for point in [Vector3(x,6.38,-8),Vector3(x,6.98,-16),Vector3(x,6.38,-8),Vector3(x,5.78,0)]:
			await play._walk(point,650)
			var shape: CollisionShape3D=play.player.get_node("Collision")
			var feet: float=play.player.position.y+shape.position.y-shape.shape.height*0.5
			print("RAMP_POINT target=",point," actual=",play.player.position," feet=",feet)
			assert(Vector2(play.player.position.x-point.x,play.player.position.z-point.z).length()<0.45,"Reaches ramp waypoint")
			assert(absf(feet-point.y)<0.12 and not play.inside,"Continuous collision at both elevations")
			if point==Vector3(16,6.38,-8) and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://captures/balcony_attachment/sloped_walkway_play.png")
	print("SLOPED_WALKWAYS_BOTH_SIDES_ASCEND_DESCEND_OK")
	play.queue_free(); for i in 3: await process_frame
	quit()
