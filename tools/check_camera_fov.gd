extends SceneTree
## Camera math and persisted authoring contract; runs headless without rendering.
const IsoCamera = preload("res://scripts/village/iso_cam.gd")
var failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CAMERA_FOV: " + message)

func screen_span(camera: Camera3D, focus: Vector3) -> float:
	var right := camera.global_basis.x * 2.0
	return camera.unproject_position(focus - right).distance_to(camera.unproject_position(focus + right))

func run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.own_world_3d = true
	root.add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var target := Node3D.new()
	target.name = "Target"
	target.position = Vector3(2, 3, -4)
	world.add_child(target)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	var camera := IsoCamera.new()
	camera.name = "IsoCam"
	camera.target_path = NodePath("../Target")
	camera.shadow_light_path = NodePath("../Sun")
	camera.ortho_size = 17.5
	camera.pitch_deg = 48.0
	camera.yaw_deg = 45.0
	camera.focus_height = 0.0
	camera.follow_rate = 0.0
	camera.pixel_snap = false
	camera.current = true
	world.add_child(camera)
	await process_frame
	var direction := camera.global_basis
	var expected_center := Vector2(view.size) * .5
	var baseline_span := 0.0
	var distances: Array[float] = []
	for angle in [0.0, 13.0, 26.0]:
		camera.perspective_fov = angle
		camera._apply(true)
		await process_frame
		var depth: float = camera.global_position.distance_to(camera._focus)
		distances.append(depth)
		check(camera.projection == (Camera3D.PROJECTION_ORTHOGONAL if angle == 0.0 else Camera3D.PROJECTION_PERSPECTIVE), "Wrong projection at FOV " + str(angle))
		check(camera.global_basis.is_equal_approx(direction), "FOV changed camera angle")
		check(camera.unproject_position(camera._focus).distance_to(expected_center) < .05, "Focus moved away from screen center")
		check(camera.project_position(expected_center, depth).distance_to(camera._focus) < .002, "Camera3D project/unproject did not roundtrip focal center")
		var span := screen_span(camera, camera._focus)
		if angle == 0.0:
			baseline_span = span
		else:
			check(absf(span - baseline_span) < .05, "Focal-plane scale changed at FOV " + str(angle))
			var expected := camera.size / (2.0 * tan(deg_to_rad(angle) * .5))
			check(absf(expected - depth) < .005, "Perspective distance does not match framing")
		check(camera.near > 0.0 and camera.near < depth and camera.far > depth, "Invalid focal clipping range")
		check(sun.directional_shadow_max_distance >= depth + maxf(30.0, camera.size * 2.0) - .01, "Sun shadow cutoff precedes the visible focal region")
		check(sun.directional_shadow_max_distance >= 60.0, "Camera reduced the original sun shadow range")
	print("CAMERA_FOV_DISTANCES ", distances, " focal_4m_span_px=", baseline_span)
	check(distances[2] < distances[1], "Increasing FOV should approach the focus while keeping its scale")
	# Programmatic near-zero values cannot divide by zero or create an invalid camera.
	camera.perspective_fov = .000001
	camera._apply(true)
	check(camera.global_transform.is_finite() and is_finite(camera.far), "Near-zero positive FOV produced nonfinite transform")
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Positive FOV silently became orthographic")
	check(camera.fov >= 1.0 and camera.near > 1.0, "Near-zero perspective lacks safe clipping slab")
	check(absf(screen_span(camera, camera._focus) - baseline_span) < .15, "Near-zero fallback changed focal scale")
	var tiny_depth: float = camera.global_position.distance_to(camera._focus)
	check(sun.directional_shadow_max_distance > tiny_depth + 30.0, "One-degree view lost focus shadows")
	check(tiny_depth - camera.near <= maxf(60.0, camera.size * 3.0) + .05, "Near-zero view wastes shadow cascades far in front of the visible world")
	# Live changes and following use the same center; hidden legacy bool remains callable.
	camera.perspective_fov = 13.0
	target.position += Vector3(2, 0, 1)
	camera._apply(false, .016)
	check(camera._focus.is_equal_approx(target.global_position), "Target follow changed with perspective")
	check(camera.unproject_position(target.global_position).distance_to(expected_center) < .05, "Follow target not centered")
	camera.perspective_enabled = false
	check(camera.perspective_fov == 0.0 and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Legacy disable alias no longer works")
	camera.perspective_enabled = true
	check(camera.perspective_fov == 20.0 and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Legacy enable alias lost its 20-degree default")
	camera.perspective_fov = 13.0
	# Existing fixed-yaw combat and optional free orbit retain their control rules.
	var opponent := Node3D.new()
	world.add_child(opponent)
	opponent.position = target.position + Vector3(4, 0, 2)
	camera._lock_target = opponent
	var fixed_yaw: float = camera._view_yaw
	camera._apply(true, .5)
	check(is_equal_approx(camera._view_yaw, fixed_yaw), "Fixed lock camera unexpectedly rotated")
	camera._lock_target = null
	camera.free_rotate = true
	Input.action_press("camera_right")
	camera._apply(false, .1)
	Input.action_release("camera_right")
	check(not is_equal_approx(camera._view_yaw, fixed_yaw), "Optional free orbit stopped working")
	camera.free_rotate = false
	camera._apply(true)
	# Confirm one public FOV control, then persist a standalone authored camera.
	for property in camera.get_property_list():
		if property.name in ["perspective_enabled", "match_perspective_framing", "fov", "projection"]:
			check((int(property.usage) & PROPERTY_USAGE_EDITOR) == 0, "Conflicting Inspector projection field: " + str(property.name))
	var packed := PackedScene.new()
	check(packed.pack(camera) == OK, "Could not pack camera")
	check(ResourceSaver.save(packed, "user://camera_fov_roundtrip.tscn") == OK, "Could not save camera settings")
	var reopened: Camera3D = (ResourceLoader.load("user://camera_fov_roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(is_equal_approx(reopened.perspective_fov, 13.0), "Saved camera lost FOV13")
	reopened.free()
	# Rig default and an old orthographic scene are inspected without starting gameplay.
	var rig: Node = load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
	check(is_equal_approx(rig.get_node("Pixel/View/IsoCam").perspective_fov, 13.0), "Gameplay rig does not default to FOV13")
	check(rig.get_node("Pixel/View/IsoCam").shadow_light_path == NodePath("../Sun"), "Gameplay rig does not bind its sun")
	rig.free()
	var legacy: Node = load("res://scenes/dev/hearth_village_playable.tscn").instantiate()
	check(legacy.get_node("Pixel/View/IsoCam").perspective_fov == 0.0, "Legacy orthographic scene changed projection")
	legacy.free()
	camera.shadow_light_path = NodePath()
	camera._apply(true)
	check(is_equal_approx(sun.directional_shadow_max_distance, 60.0), "Removing the optional sun binding did not restore its original range")
	view.free()
	print("CAMERA_FOV_", "PASS" if failures.is_empty() else "FAIL", ": focal-plane scale/center at 0,13,26; near-zero safety and sun shadows; follow/lock/orbit; Inspector and saved-scene compatibility")
	quit(0 if failures.is_empty() else 1)
