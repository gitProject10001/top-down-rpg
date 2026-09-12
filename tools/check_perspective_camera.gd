extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/dev/oak_billboard_playable.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var view = scene.get_node("Pixel/View")
	var cam = view.get_node("IsoCam")
	cam.perspective_enabled = true
	for frame in range(60): await process_frame
	assert(cam.projection == Camera3D.PROJECTION_PERSPECTIVE)
	assert(is_equal_approx(cam.fov,20.0))
	var expected: float = cam.size/(2.0*tan(deg_to_rad(cam.fov)*0.5))
	assert(absf(cam.global_position.distance_to(cam._focus)-expected)<0.01)
	for i in range(4):
		cam._free_yaw = i*PI/2
		for frame in range(10): await process_frame
		assert(cam.global_transform.is_finite())
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://art_source/tuft_flow/perspective_game.png")
	cam.perspective_enabled = false
	for frame in range(2): await process_frame
	assert(cam.projection == Camera3D.PROJECTION_ORTHOGONAL)
	print("PERSPECTIVE_PASS: FOV20, distance=",expected,"; four yaw angles, orthographic fallback")
	quit()
