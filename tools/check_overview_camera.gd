extends SceneTree
## Full integration and real rendering: overview must survive repeated projection
## changes, preserve the authored lens/zoom and resume following on return.
## --legacy-f8 exercises the former shortcut before the editor-safe binding fix.
var failures: Array[String] = []
var scene: Node3D
var view: SubViewport
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("OVERVIEW_CHECK: " + message)

func settle(frames := 20) -> void:
	for frame in frames:
		await physics_frame

func key_event(code: Key, pressed: bool, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift
	Input.parse_input_event(event)

func press(code: Key, shift := false) -> void:
	key_event(code, true, false, shift)
	await process_frame
	key_event(code, false, false, shift)
	await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png("res://captures/overview_" + name + ".png") == OK, "Could not capture " + name)

func run() -> void:
	var legacy := "--legacy-f8" in OS.get_cmdline_user_args()
	var code: Key = KEY_F8 if legacy else KEY_O
	scene = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
	root.add_child(scene)
	await settle(90)
	view = scene.get_node("GameplayPreviewRig/Pixel/View")
	view.get_parent().stretch = false
	view.size = Vector2i(1152, 648)
	camera = scene.camera
	var sun := view.get_node("Sun") as DirectionalLight3D
	var environment := (view.get_node("WorldEnvironment") as WorldEnvironment).environment
	var debug := root.get_node("Dbg")
	var original_clean: bool = debug.clean
	check(environment.sdfgi_enabled, "Regression must include SDFGI")
	print("OVERVIEW_BEGIN renderer=", DisplayServer.get_name(), " debugger=", EngineDebugger.is_active(), " viewport=", view.size, " shortcut=", OS.get_keycode_string(code))
	for lens in [13.0, 0.0]:
		camera.perspective_fov = lens
		camera.ortho_size = 17.5
		camera._apply(true)
		await settle(35)
		var yaw: float = camera._view_yaw
		for cycle in 3:
			await press(code)
			check(scene.overview, "Overview key did not enter overview")
			await settle(45)
			check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(camera.size, 145.0), "Overview projection/scale is wrong")
			check(camera.global_transform.is_finite() and camera.far > camera.near, "Overview camera is invalid")
			check(is_finite(sun.directional_shadow_max_distance), "Overview shadow range is invalid")
			key_event(code, true, true)
			await process_frame
			check(scene.overview, "Key echo toggled overview")
			key_event(code, false)
			if lens == 13.0 and cycle == 0: await capture("map")
			await press(code)
			await settle(45)
			check(not scene.overview and camera.is_processing() and camera.is_physics_processing(), "Gameplay camera did not resume")
			check(is_equal_approx(camera.perspective_fov, lens) and is_equal_approx(camera.ortho_size, 17.5), "Overview lost the authored lens or zoom")
			check(is_equal_approx(camera._view_yaw, yaw), "Overview changed the gameplay angle")
			check(camera.projection == (Camera3D.PROJECTION_ORTHOGONAL if lens == 0.0 else Camera3D.PROJECTION_PERSPECTIVE), "Wrong restored projection")
			check(debug.clean == original_clean, "Overview shortcut also changed debug visibility")
			print("OVERVIEW_ROUNDTRIP lens=", lens, " cycle=", cycle, " shadow_range=", sun.directional_shadow_max_distance)
		if lens == 13.0: await capture("returned_gameplay")
	# Follow must resume after the repeated overview exits.
	var before: Vector3 = camera._focus
	scene.player.position += Vector3(2, 0, 0)
	await settle(45)
	check(camera._focus.distance_to(before) > 1.0, "Camera remained frozen after overview")
	if not legacy and not EngineDebugger.is_active():
		await press(KEY_F8)
		check(scene.overview and debug.clean == original_clean, "Standalone F8 alias failed or changed debug visibility")
		await settle(20)
		await press(KEY_F8)
		check(not scene.overview, "Standalone F8 alias did not return to gameplay")
	if not legacy:
		var original_boxes: bool = debug.show_hitboxes
		var fps_label: Label = root.get_node("Hud")._fps_lbl
		var original_fps_visible := fps_label.visible
		await press(KEY_F3, true)
		check(debug.clean != original_clean and debug.show_hitboxes == original_boxes, "Shift+F3 did not exclusively toggle clean view")
		check(fps_label.visible == original_fps_visible, "Shift+F3 leaked to the ordinary F3 HUD shortcut")
		await press(KEY_F3, true)
		check(debug.clean == original_clean, "Clean view did not restore")
	await settle(30)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	scene.queue_free()
	await process_frame
	await process_frame
	print("OVERVIEW_", "PASS" if failures.is_empty() else "FAIL", ": six full-scene roundtrips at FOV13/0 with SDFGI, key echoes and resumed follow")
	quit(0 if failures.is_empty() else 1)
