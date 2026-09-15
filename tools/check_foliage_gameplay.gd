extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func check() -> void:
    var scene = load("res://scenes/dev/foliage_study.tscn").instantiate()
    root.add_child(scene)
    var view = scene.get_node("GameplayPreviewRig/Pixel/View")
    var player = view.get_node("Player")
    var camera = view.get_node("IsoCam")
    assert(camera.get_script() == load("res://scripts/village/iso_cam.gd"))
    assert(camera.ortho_size == 17.5 and camera.pitch_deg == 48.0)
    assert(camera._target == player)
    assert(view.has_node("VillageCharacterPalette") and view.has_node("PixelSnap"))
    assert(view.has_node("Broadleaf") and view.has_node("Pine"))
    assert(not view.has_node("WorldStream") and not view.has_node("Camp"))
    for i in 30: await physics_frame
    var start: Vector3 = player.position
    var camera_start: Vector3 = camera.position
    Input.action_press("move_down")
    for i in 60: await physics_frame
    Input.action_release("move_down")
    for i in 30: await physics_frame
    assert(player.position.distance_to(start) > 1.0, "Gameplay input must reach the subviewport player")
    assert(camera.position.distance_to(camera_start) > 1.0, "Camera must follow")
    assert(player.is_on_floor(), "Ground collision with the main-scene player collider")
    print("FOLIAGE_GAMEPLAY_PASS: movement, follow camera, presentation and ground")
    scene.queue_free()
    for i in 3: await process_frame
    quit()
