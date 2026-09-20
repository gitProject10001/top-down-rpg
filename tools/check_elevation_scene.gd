extends SceneTree
## Full-scene acceptance: elevated ground is real collision, vegetation is rooted,
## access ramps are walkable, regeneration and F7 preserve the two states.
var failures: Array[String] = []
var scene: Node3D
var view: SubViewport
var player: CharacterBody3D
var camera: Camera3D
var foot_offset: float
var ray_exclusions: Array[RID] = []
var cliffs: Array[Node3D] = []

func _initialize() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> bool:
    if not condition:
        failures.append(message)
        push_error("ELEVATION_CHECK: " + message)
    return condition

func settle(frames: int = 30) -> void:
    for frame in frames:
        await physics_frame

func surface_height(cliff: Node3D, world: Vector3) -> float:
    var local := cliff.to_local(world)
    var height: float = cliff.height_at_local(Vector2(local.x, local.z))
    if is_nan(height): return NAN
    return cliff.to_global(Vector3(local.x, height, local.z)).y

func ground_ray(world: Vector3) -> Dictionary:
    var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * 35.0, world - Vector3.UP * 40.0)
    query.exclude = ray_exclusions
    return player.get_world_3d().direct_space_state.intersect_ray(query)

func release_movement() -> void:
    for action in ["move_left", "move_right", "move_up", "move_down"]:
        Input.action_release(action)

func walk_to(target: Vector3, max_frames: int = 480) -> bool:
    for frame in max_frames:
        var delta := target - player.global_position
        delta.y = 0.0
        if delta.length() < .45:
            release_movement()
            await settle(12)
            return true
        var local := delta.normalized().rotated(Vector3.UP, -camera.global_rotation.y)
        release_movement()
        if absf(local.x) > .02:
            Input.action_press("move_right" if local.x > 0 else "move_left", absf(local.x))
        if absf(local.z) > .02:
            Input.action_press("move_down" if local.z > 0 else "move_up", absf(local.z))
        await physics_frame
    release_movement()
    return false

func capture(name: String) -> void:
    await settle(25)
    await RenderingServer.frame_post_draw
    check(view.get_texture().get_image().save_png("res://captures/elevation_" + name + ".png") == OK,
        "Could not save " + name)

func coverage_at(grass: Node3D, point: Vector3) -> Color:
    var uv: Vector2 = (Vector2(point.x, point.z) - grass.mask_center) / grass.mask_size + Vector2.ONE * .5
    check(uv.x > 0 and uv.y > 0 and uv.x < 1 and uv.y < 1, "Raised stamp lies outside expanded coverage")
    var image: Image = grass.coverage
    return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1),
        clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1))

func grass_chunk_count(grass: Node3D, point: Vector3) -> int:
    # MultiMesh per-instance transforms are renderer-owned and cannot be read
    # reliably from the dummy headless renderer. The retained instance count is
    # sufficient when an erase stamp covers this complete eight-metre chunk.
    var key := Vector2i(floori(point.x / grass.CHUNK), floori(point.z / grass.CHUNK))
    if not grass.chunks.has(key): return 0
    var count := 0
    for node in grass.chunks[key].get_children():
        if node is MultiMeshInstance3D and node.name != "PathPebbles":
            count += node.multimesh.instance_count
    return count

func check_raised_coverage() -> void:
    var cliff: Node3D = cliffs[0]
    var length_value: float = cliff.guide.get_baked_length()
    var frame: Dictionary = cliff._frame(length_value * .6, length_value)
    var local: Vector3 = frame.center - frame.front * (cliff.wall_depth + cliff.raised_zone_depth * .88)
    local.y = cliff.height_at_local(Vector2(local.x, local.z))
    var world := cliff.to_global(local)
    player.global_position = world + Vector3.UP * (foot_offset + .1)
    player.velocity = Vector3.ZERO
    await settle(60)
    var grass = scene.art_direction.grass
    var before := coverage_at(grass, world)
    var baseline_count := grass_chunk_count(grass, world)
    check(baseline_count > 10, "Baseline raised stamp area needs real grass")
    var old_road_uv: Vector2 = (Vector2(world.x, world.z) - grass.road_mask_center) / grass.road_mask_size + Vector2.ONE * .5
    check(old_road_uv.y < 0.0, "Coverage regression must exercise the area beyond the legacy mask")
    var layers := view.get_node("ArtStudyLayers")
    var profile: Resource = layers.profile.duplicate(true)
    var edit = preload("res://scripts/art/art_surface_edit.gd").new()
    edit.stable_id = "elevation_density_regression"
    edit.surface_path = view.get_path_to(cliff)
    edit.layer = 0
    edit.local_position = local
    edit.radius = 12.0
    edit.intensity = -1.0
    edit.locked = true
    profile.add_edit(edit)
    var palette = preload("res://scripts/art/art_surface_edit.gd").new()
    palette.stable_id = "elevation_palette_regression"
    palette.surface_path = edit.surface_path
    palette.layer = 1
    palette.local_position = local
    palette.radius = 12.0
    palette.intensity = .35
    profile.add_edit(palette)
    layers.profile = profile
    layers.regenerate()
    await settle(60)
    grass = scene.art_direction.grass
    var painted := coverage_at(grass, world)
    var erased_count := grass_chunk_count(grass, world)
    # At the exact outer mesh boundary, a 512px control-map texel can straddle
    # inside/outside: allow <1% fringe instances, but require zero in the interior.
    check(painted.g < .01 and erased_count < baseline_count * .01,
        "Local density erase must remove >99% of raised-surface scatter")
    for x in [-2.0, 0.0, 2.0]:
        for z in [-2.0, 0.0, 2.0]:
            check(coverage_at(grass, world + Vector3(x, 0, z)).g < .01,
                "Density erase must be zero throughout the stamp interior")
    check(painted.b > before.b + .10, "Raised-surface palette stamp did not reach shared coverage")
    var ground: MeshInstance3D = cliff.get_node("_GeneratedContinuousCliff/ElevatedGround")
    check(ground.material_override.get_shader_parameter("art_coverage") == grass.shared_coverage,
        "Raised terrain and scatter do not share the same painted mask")
    check(ground.material_override.get_shader_parameter("art_coverage_center").is_equal_approx(grass.mask_center)
        and ground.material_override.get_shader_parameter("art_coverage_size").is_equal_approx(grass.mask_size),
        "Raised shader uses different coverage bounds from the scatter")
    cliff.rebuild()
    await settle(65)
    grass = scene.art_direction.grass
    check(coverage_at(grass, world).is_equal_approx(painted), "Cliff rebuild lost local density/palette edits")
    check(profile.find_edit(edit.stable_id) == edit and edit.locked, "Regeneration replaced or unlocked authored stamp")
    check(not profile.set_edit_deleted(edit.stable_id, true), "Locked density stamp must resist procedural deletion")
    profile.set_edit_deleted(palette.stable_id, true)
    layers.regenerate()
    await settle(45)
    grass = scene.art_direction.grass
    var tombstoned := coverage_at(grass, world)
    check(absf(tombstoned.b - before.b) < .01 and tombstoned.g < .01,
        "Deleting only the palette stroke must preserve the independent density erase")
    print("ELEVATION_COVERAGE_RESULT baseline_instances=", baseline_count, " remaining_boundary_instances=", erased_count,
        " original_mask_uv=", old_road_uv, " stable_surface=", edit.surface_path, " failures=", failures)

func check_safe_f7() -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = KEY_F7
    for cliff in cliffs:
        var length_value: float = cliff.guide.get_baked_length()
        var frame: Dictionary = cliff._frame(length_value * .5, length_value)
        var local: Vector3 = frame.center - frame.front * (cliff.wall_depth + cliff.raised_zone_depth * .5)
        var upper := cliff.to_global(local)
        upper.y = surface_height(cliff, upper) + foot_offset
        player.global_position = upper + Vector3.UP * .1
        player.velocity = Vector3.ZERO
        await settle(50)
        check(player.is_on_floor(), "F7 scenario must start standing on elevated terrain")
        var original_upper := player.global_position
        scene._unhandled_key_input(event)
        await settle(60)
        var safe := player.global_position
        var hit := ground_ray(safe)
        check(player.is_on_floor() and not hit.is_empty() and safe.y < original_upper.y - 2.0,
            "F7 must place the player on safe original ground instead of falling outside the old terrain")
        if not hit.is_empty():
            check(absf(safe.y - foot_offset - hit.position.y) < .15, "Safe F7 position is not grounded")
        scene._unhandled_key_input(event)
        await settle(50)
        check(player.is_on_floor() and player.global_position.distance_to(original_upper) < .15,
            "Re-enabling painted mode must restore an unmoved player's upper position")
        # Inspector changes rebuild physical ground before the art refresh.
        # The real actor must be lifted out of the updated surface.
        var authored_height: float = cliff.wall_height
        cliff.wall_height = authored_height + 1.0
        await settle(70)
        var raised_support := surface_height(cliff, player.global_position)
        check(player.is_on_floor() and absf(player.global_position.y - foot_offset - raised_support) < .15,
            "A live height increase buried the player inside the rebuilt plateau")
        check(player.global_position.y > original_upper.y + .85, "Live height change did not raise the standing player")
        scene._unhandled_key_input(event)
        await settle(40)
        cliff.wall_height = authored_height + 1.5
        await settle(50)
        scene._unhandled_key_input(event)
        await settle(50)
        raised_support = surface_height(cliff, player.global_position)
        check(player.is_on_floor() and absf(player.global_position.y - foot_offset - raised_support) < .15,
            "F7 return ignored a plateau height change made in original mode")
        cliff.wall_height = authored_height
        await settle(70)
        check(player.is_on_floor() and absf(player.global_position.y - original_upper.y) < .15,
            "Restoring authored height left the player floating")
        # Walking away in original mode cancels the saved return location.
        scene._unhandled_key_input(event)
        await settle(40)
        player.global_position += Vector3(1.2, 0, 0)
        await settle(20)
        var moved := player.global_position
        scene._unhandled_key_input(event)
        await settle(20)
        check(Vector2(moved.x, moved.z).distance_to(Vector2(player.global_position.x, player.global_position.z)) < .15,
            "F7 must not teleport a player who moved away in original mode")
        print("ELEVATION_F7_PLAYER ", cliff.get_parent().name, " upper=", original_upper, " safe=", safe,
            " returned_live_height_and_cancelled=", failures.is_empty())

func run() -> void:
    scene = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
    var f7_only := "--f7-only" in OS.get_cmdline_user_args()
    var coverage_only := "--coverage-only" in OS.get_cmdline_user_args()
    if f7_only or coverage_only:
        for child in scene.get_children():
            if child.name not in ["TerrenoComposto", "Boschi", "Fiume", "Lago", "ArtStudyLayers", "Affioramento_0", "Affioramento_1"]:
                scene.remove_child(child)
                child.free()
    var original_trees: Dictionary = {}
    for tree in scene.get_node("Boschi").get_children():
        if tree is Node3D:
            original_trees[str(tree.name)] = tree.transform
    root.add_child(scene)
    await settle(60)
    view = scene.get_node("GameplayPreviewRig/Pixel/View")
    view.get_parent().stretch = false
    view.size = Vector2i(1152, 648)
    player = scene.player
    camera = scene.camera
    var body_shape: CollisionShape3D = player.get_node("Collision")
    foot_offset = body_shape.shape.height * .5 - body_shape.position.y
    ray_exclusions.append(player.get_rid())
    for body in view.get_node("Boschi").find_children("*", "CollisionObject3D", true, false):
        ray_exclusions.append(body.get_rid())
    for candidate in scene.art_direction.cliffs:
        if candidate.has_method("height_at_local") and candidate.raised_zone_enabled:
            cliffs.append(candidate)
    if not check(not cliffs.is_empty(), "Integrated scene must enable raised terrain"):
        scene.queue_free()
        quit(1)
        return
    if f7_only:
        await check_safe_f7()
        print("ELEVATION_F7_RESULT failures=", failures)
        scene.queue_free()
        await process_frame
        cliffs.clear()
        call_deferred("quit", 0 if failures.is_empty() else 1)
        return
    if coverage_only:
        await check_raised_coverage()
        scene.queue_free()
        await process_frame
        cliffs.clear()
        call_deferred("quit", 0 if failures.is_empty() else 1)
        return
    check(is_equal_approx(camera.perspective_fov, 13.0), "Gameplay camera must start at FOV 13")
    scene.toggle_overview()
    check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "F8 must use orthographic overview")
    scene.toggle_overview()
    await settle(5)
    check(is_equal_approx(camera.perspective_fov, 13.0), "F8 must restore gameplay perspective")
    var main: Node3D = cliffs[0]
    var guide: Curve3D = main.guide
    var length_value := guide.get_baked_length()
    var frame: Dictionary = main._frame(length_value * .5, length_value)
    var back_depth: float = main.wall_depth + main.raised_zone_depth * .45
    var center_local: Vector3 = frame.center - frame.front * back_depth
    var center := main.to_global(center_local)
    center.y = surface_height(main, center)
    if not check(not is_nan(center.y), "Central plateau point must be inside generated ground"):
        quit(1)
        return
    var probes := 0
    for cliff in cliffs:
        var generated := cliff.get_node("_GeneratedContinuousCliff")
        var ground: MeshInstance3D = generated.get_node("ElevatedGround")
        check(ground.mesh != null, "Raised terrain needs a rendered mesh")
        check(generated.has_node("ElevatedGroundCollision"), "Raised terrain needs actual collision")
        var material: Material = ground.material_override if ground.material_override else ground.get_active_material(0)
        check(material is ShaderMaterial and material.shader.resource_path.ends_with("ground_clear.gdshader"),
            "Raised ground must share the meadow material")
        var geometry: Dictionary = cliff.generate()
        # Every crest joins the ground and shares the same analytical height.
        for i in range(2, geometry.crests.size() - 2, 9):
            var crest: Vector3 = geometry.crests[i]
            var height: float = cliff.height_at_local(Vector2(crest.x, crest.z))
            check(not is_nan(height) and absf(height - crest.y) < .035, "A gap exists between cliff crest and elevated ground")
        var cliff_length: float = cliff.guide.get_baked_length()
        for along in [.18, .5, .82]:
            var local_frame: Dictionary = cliff._frame(cliff_length * along, cliff_length)
            for back in [.35, .65]:
                var local: Vector3 = local_frame.center - local_frame.front * (cliff.wall_depth + cliff.raised_zone_depth * back)
                var p := cliff.to_global(local)
                var expected := surface_height(cliff, p)
                if is_nan(expected): continue
                var hit := ground_ray(p)
                check(not hit.is_empty() and absf(hit.position.y - expected) < .06,
                    "Plateau query/collision mismatch at " + str(p))
                probes += 1
    check(probes >= 8, "Insufficient independent plateau collision samples")
    var raised_trees := 0
    var painted_tree_transforms: Dictionary = {}
    for tree in view.get_node("Boschi").get_children():
        if not tree is Node3D: continue
        painted_tree_transforms[str(tree.name)] = tree.transform
        var original: Transform3D = original_trees[str(tree.name)]
        check(Vector2(tree.position.x, tree.position.z).is_equal_approx(Vector2(original.origin.x, original.origin.z)),
            "Tree XZ changed: " + str(tree.name))
        for cliff in cliffs:
            var expected := surface_height(cliff, tree.global_position)
            if is_nan(expected) or expected < original.origin.y + .2: continue
            check(absf(tree.global_position.y - expected) < .10, "Tree is buried or floating: " + str(tree.name))
            raised_trees += 1
            break
    check(raised_trees > 0, "Existing trees must be rooted on the raised zone")
    # Real player traversal: follow the access ramp from its lower end onto the plateau.
    var end_frame: Dictionary = main._frame(length_value, length_value)
    var ramp_length: float = main.effective_ramp_length()
    var end_local: Vector3 = end_frame.center - end_frame.front * back_depth
    var start_local: Vector3 = end_local + end_frame.direction * (ramp_length - 1.3)
    var start := main.to_global(start_local)
    start.y = surface_height(main, start)
    var ramp_target := main.to_global(end_local - end_frame.direction * 2.0)
    ramp_target.y = surface_height(main, ramp_target)
    check(not is_nan(start.y) and not is_nan(ramp_target.y), "Access ramp must join plateau")
    player.global_position = start + Vector3.UP * (foot_offset + .15)
    player.velocity = Vector3.ZERO
    await settle(50)
    var starting_y := player.global_position.y
    print("RAMP_START planned=", start, " actual=", player.global_position, " floor=", player.is_on_floor(),
        " hit=", ground_ray(start), " collision_mask=", player.collision_mask)
    check(player.is_on_floor(), "Player cannot stand on lower ramp")
    check(await walk_to(ramp_target), "Player could not climb the access ramp")
    print("RAMP_END target=", ramp_target, " actual=", player.global_position, " floor=", player.is_on_floor())
    check(player.is_on_floor() and player.global_position.y > starting_y + 2.0,
        "Ramp movement must gain real elevation while grounded")
    var top_target := main.to_global(end_local - end_frame.direction * 6.0)
    top_target.y = surface_height(main, top_target)
    check(await walk_to(top_target), "Player cannot walk across the raised plateau")
    check(player.is_on_floor() and absf(player.global_position.y - foot_offset - top_target.y) < .15,
        "Player feet do not meet elevated collision")
    player.global_position = center + Vector3.UP * (foot_offset + .15)
    player.velocity = Vector3.ZERO
    await settle(50)
    var grass = scene.art_direction.grass
    var elevated_grass := 0
    for chunk in grass.chunks.values():
        for node in chunk.get_children():
            if not node is MultiMeshInstance3D or node.name == "PathPebbles": continue
            for index in range(0, node.multimesh.instance_count, 13):
                var position: Vector3 = node.to_global(node.multimesh.get_instance_transform(index).origin)
                var expected := surface_height(main, position)
                if is_nan(expected) or expected < 1.0: continue
                check(absf(position.y + .008 - expected) < .07, "Grass is embedded in elevated ground")
                elevated_grass += 1
    check(elevated_grass > 30, "Raised terrain has no real grass")
    await capture("upper_zone_player")
    # Capture the cliff face and its top from the same fixed focal plane.
    camera._target = null
    camera._have_focus = true
    camera._focus = main.to_global(frame.center - frame.front * 4.0 + Vector3.UP * 2.4)
    camera.ortho_size = 28.0
    camera.perspective_fov = 13.0
    await capture("cliff_fov13")
    var fov13_focus := camera.unproject_position(camera._focus)
    camera.perspective_fov = 0.0
    await capture("cliff_fov0")
    check(camera.unproject_position(camera._focus).distance_to(fov13_focus) < .5,
        "FOV switch moved the focal framing")
    camera.perspective_fov = 13.0
    var physical_before := ground_ray(center)
    var original_mode_event := InputEventKey.new()
    original_mode_event.pressed = true
    original_mode_event.keycode = KEY_F7
    scene._unhandled_key_input(original_mode_event)
    await settle(8)
    check(not scene.art_direction.enabled, "F7 did not disable painted mode")
    for tree in view.get_node("Boschi").get_children():
        if tree is Node3D:
            check(tree.transform.is_equal_approx(original_trees[str(tree.name)]), "F7 did not restore tree positions")
    var physical_original := ground_ray(center)
    check(physical_original.is_empty() or physical_original.position.y < physical_before.position.y - 1.0,
        "F7 left invisible elevated collision in original mode")
    scene._unhandled_key_input(original_mode_event)
    await settle(35)
    for tree in view.get_node("Boschi").get_children():
        if tree is Node3D:
            check(tree.transform.is_equal_approx(painted_tree_transforms[str(tree.name)]), "F7 did not restore elevated trees")
    # An authored local offset must survive both states and the layer toggle.
    var edited_tree: Node3D
    for tree in view.get_node("Boschi").get_children():
        if tree is Node3D and tree.transform.origin.y > original_trees[str(tree.name)].origin.y + 1.0:
            edited_tree = tree
            break
    if check(edited_tree != null, "Need one raised tree to verify manual offsets"):
        var delta := Vector3(.07, .2, 0)
        var baseline: Transform3D = painted_tree_transforms[str(edited_tree.name)]
        edited_tree.position += delta
        scene.art_direction.apply(false)
        check(edited_tree.position.is_equal_approx(original_trees[str(edited_tree.name)].origin + delta),
            "F7 discarded the manually edited tree offset in original mode")
        scene.art_direction.apply(true)
        check(edited_tree.position.is_equal_approx(baseline.origin + delta),
            "F7 discarded the manually edited tree offset in painted mode")
        edited_tree.position -= delta
        scene.art_direction.apply(false)
        scene.art_direction.apply(true)
        scene.art_direction.profile.cliffs_enabled = false
        scene.art_direction.apply(true)
        check(scene.art_direction.enabled and edited_tree.position.is_equal_approx(original_trees[str(edited_tree.name)].origin),
            "Disabling only the cliff layer did not restore tree elevation")
        scene.art_direction.profile.cliffs_enabled = true
        scene.art_direction.apply(true)
        check(edited_tree.position.is_equal_approx(baseline.origin), "Re-enabling cliff layer lost tree elevation")
    var heights_before := PackedFloat32Array()
    for z in [-2.0, 0.0, 2.0]:
        heights_before.append(surface_height(main, center + Vector3(0, 0, z)))
    main.rebuild()
    await settle(45)
    for i in 3:
        check(is_equal_approx(heights_before[i], surface_height(main, center + Vector3(0, 0, [-2.0, 0.0, 2.0][i]))),
            "Regeneration changed deterministic elevation")
    var rebuilt_ground: MeshInstance3D = main.get_node("_GeneratedContinuousCliff/ElevatedGround")
    var rebuilt_material: Material = rebuilt_ground.material_override if rebuilt_ground.material_override else rebuilt_ground.get_active_material(0)
    check(rebuilt_material is ShaderMaterial and rebuilt_material.get_shader_parameter("anime_painted") == true,
        "Regeneration lost the painted ground material")
    var after_hit := ground_ray(center)
    check(not after_hit.is_empty() and absf(after_hit.position.y - center.y) < .06,
        "Regeneration lost elevated collision")
    release_movement()
    print("ELEVATION_SCENE_RESULT surfaces=", cliffs.size(), " probes=", probes, " rooted_trees=", raised_trees,
        " grass_samples=", elevated_grass, " ramp_rise=", ramp_target.y + foot_offset - starting_y, " failures=", failures)
    scene.queue_free()
    await process_frame
    await process_frame
    cliffs.clear()
    call_deferred("quit", 0 if failures.is_empty() else 1)
