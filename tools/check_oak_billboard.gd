extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/dev/oak_billboard_playable.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var view = scene.get_node("Pixel/View")
	var oak = view.get_node("OakBillboardSample")
	var cam := Camera3D.new()
	view.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 13
	cam.current = true
	for i in range(4):
		var angle := i*TAU/4
		cam.position = oak.position+Vector3(sin(angle)*12,20,cos(angle)*12)
		cam.look_at(oak.position+Vector3.UP*2.7)
		for frame in range(20): await process_frame
		var facing: Vector3 = oak.get_node("BillboardCrown").global_basis.z.normalized()
		assert(Vector2(facing.x,facing.z).normalized().dot(Vector2(cam.global_basis.z.x,cam.global_basis.z.z).normalized()) < -0.99)
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png("res://art_source/tuft_flow/oak_ingame_%d.png"%i)
	print("OAK_BILLBOARD_PASS: four angles in playable scene")
	quit()
