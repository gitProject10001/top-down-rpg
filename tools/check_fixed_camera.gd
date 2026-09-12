extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/dev/hearth_village_playable.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var cam = scene.get_node("Pixel/View/IsoCam")
	var p = scene.get_node("Pixel/View/Player")
	for frame in range(5): await process_frame
	assert(not cam.perspective_enabled and not cam.free_rotate and not cam.lock_rotate)
	assert(cam.projection == Camera3D.PROJECTION_ORTHOGONAL)
	var initial: float = cam._view_yaw
	Input.action_press("camera_right")
	for frame in range(5): await process_frame
	Input.action_release("camera_right")
	assert(is_equal_approx(initial,cam._view_yaw))
	var opponent := Node3D.new()
	cam.get_parent().add_child(opponent)
	opponent.position = p.position+Vector3(3,0,2)
	cam._lock_target = opponent
	for frame in range(5): await process_frame
	assert(is_equal_approx(initial,cam._view_yaw))
	p.intent.set_physics_process(false)
	for turn in [0.0,PI]:
		p.visuals.global_basis = Basis(Vector3.UP,cam.global_rotation.y+turn)
		p.intent._update_direction_frame()
		assert(p.intent._mirror_screen == (turn == PI))
	for mirrored in [false,true]:
		p.intent._mirror_screen = mirrored
		for d in SwingDir.ALL:
			assert(p.intent.screen_direction(p.intent.local_direction(d)) == d)
		assert(p.intent.local_direction(SwingDir.RIGHT) == (SwingDir.LEFT if mirrored else SwingDir.RIGHT))
		assert(p.intent.local_direction(SwingDir.UP) == SwingDir.UP)
	cam._lock_target = null
	cam.free_rotate = true
	Input.action_press("camera_right")
	for frame in range(5): await process_frame
	Input.action_release("camera_right")
	assert(not is_equal_approx(initial,cam._view_yaw))
	print("FIXED_CAMERA_PASS: orthographic, fixed free/lock yaw, optional orbit, directional round trips")
	current_scene = null
	scene.queue_free()
	await process_frame
	quit()
