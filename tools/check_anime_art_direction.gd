extends SceneTree
## Real-render A/B captures plus invariants for the runtime art profile.
func _initialize() -> void:
    call_deferred("run")

func settle(frames: int = 30) -> void:
    for i in frames:
        await physics_frame

func capture(view: SubViewport, name: String) -> void:
    await settle()
    await RenderingServer.frame_post_draw
    var error := view.get_texture().get_image().save_png("res://captures/anime_" + name + ".png")
    assert(error == OK)

func own_preview(node: Node, owner_root: Node) -> void:
    node.owner = owner_root
    for child in node.get_children():
        own_preview(child, owner_root)

func copy_visual(source: Node) -> Node:
    var copy: Node
    if source is MeshInstance3D:
        var mesh := MeshInstance3D.new()
        mesh.mesh = source.mesh
        mesh.material_override = source.material_override
        mesh.cast_shadow = source.cast_shadow
        mesh.extra_cull_margin = source.extra_cull_margin
        for i in source.get_surface_override_material_count():
            mesh.set_surface_override_material(i,source.get_surface_override_material(i))
        copy = mesh
    elif source is MultiMeshInstance3D:
        var mesh := MultiMeshInstance3D.new()
        mesh.multimesh = source.multimesh
        mesh.cast_shadow = source.cast_shadow
        copy = mesh
    elif source is Camera3D:
        var camera := Camera3D.new()
        camera.projection = source.projection
        camera.size = source.size
        camera.near = source.near
        camera.far = source.far
        camera.current = true
        copy = camera
    elif source is Light3D or source is WorldEnvironment:
        copy = source.duplicate(0)
    elif source is Node3D and not source is CollisionShape3D:
        copy = Node3D.new()
    else:
        return null
    copy.name = source.name
    if copy is Node3D:
        copy.transform = source.transform
        copy.visible = source.visible
    for child in source.get_children(true):
        var visual := copy_visual(child)
        if visual != null:
            copy.add_child(visual)
    return copy

func export_editor_preview(view: SubViewport) -> void:
    # A static, inspectable snapshot. No runtime scripts or instanced-scene
    # overrides: procedural meshes and the actual painted materials are saved.
    var preview := Node3D.new()
    preview.name = "AnimeRiverEditorPreview"
    for child in view.get_children():
        if child.name == "Player":
            continue
        if child is Node3D or child is WorldEnvironment:
            var copy := copy_visual(child)
            if copy != null:
                preview.add_child(copy)
                own_preview(copy,preview)
    var packed := PackedScene.new()
    assert(packed.pack(preview)==OK)
    var path := "res://scenes/dev/anime_river_editor_preview.scn"
    assert(ResourceSaver.save(packed,path)==OK)
    preview.free()
    var saved = load(path).instantiate()
    assert(saved.get_node("PaintedGrass").get_child_count()>0)
    assert(saved.get_node("Fiume/WaterSurface") is MeshInstance3D)
    assert(saved.get_node("TerrenoComposto/Superficie").material_override.get_shader_parameter("anime_painted"))
    assert(is_equal_approx(saved.get_node("Sun").light_angular_distance,view.get_node("Sun").light_angular_distance))
    var check_view := SubViewport.new()
    check_view.size = view.size
    check_view.own_world_3d = true
    check_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(check_view)
    check_view.add_child(saved)
    await capture(check_view,"editor_preview")
    check_view.queue_free()
    await process_frame
    print("EDITOR_PREVIEW_SAVED ",path)

func run() -> void:
    var scene = load("res://scenes/dev/integrated_landscape.tscn").instantiate()
    var river_only := "--river-only" in OS.get_cmdline_user_args()
    if river_only:
        for child in scene.get_children():
            if child.name not in ["TerrenoComposto", "Boschi", "Fiume", "Lago"]:
                scene.remove_child(child)
                child.free()
    root.add_child(scene)
    await settle(90)
    var view: SubViewport = scene.get_node("GameplayPreviewRig/Pixel/View")
    scene.player.position = Vector3(-9, 1, 24)
    scene.player.velocity = Vector3.ZERO
    await settle(90)
    var ground: MeshInstance3D = view.get_node("TerrenoComposto/Superficie")
    var geometry: Array[Dictionary] = []
    for mesh in view.get_node("Boschi").find_children("*", "MeshInstance3D", true, false):
        geometry.append({"node": mesh, "mesh": mesh.mesh, "transform": mesh.global_transform})
    var painted = ground.material_override
    assert(painted.get_shader_parameter("anime_painted") == true)
    scene.art_direction.apply(false)
    var original = ground.material_override
    assert(original != painted)
    await capture(view, "river_before")
    scene.art_direction.apply(true)
    assert(ground.material_override == painted)
    for record in geometry:
        assert(record.node.mesh == record.mesh and record.node.global_transform == record.transform)
    await capture(view, "river_after")
    var grass = scene.art_direction.grass
    var count := 0
    var varieties := [0,0,0,0]
    for chunk in grass.chunks.values():
        for kind in 12:
            var amount: int = chunk.get_child(kind).multimesh.instance_count
            count += amount
            varieties[kind/3] += amount
    assert(grass.blades.size()==12)
    for family in 4:
        assert(varieties[family]>0, "Every grass family must be represented")
    for kind in 12:
        for other in range(kind):
            assert(grass.blades[kind].get_aabb()!=grass.blades[other].get_aabb())
    for change in scene.art_direction.changes:
        if change.get("property","")=="mesh":
            if change.after.has_meta("painted_canopy"):
                assert(change.after.get_aabb().size.length()<=change.before.get_aabb().size.length()*1.05)
                continue
            for surface in change.before.get_surface_count():
                var before: Array = change.before.surface_get_arrays(surface)
                var after: Array = change.after.surface_get_arrays(surface)
                assert(before[Mesh.ARRAY_VERTEX]==after[Mesh.ARRAY_VERTEX])
                assert(before[Mesh.ARRAY_INDEX]==after[Mesh.ARRAY_INDEX])
    assert(count > 100, "3D grass must be present on the dry bank")
    assert(grass.blade.get_aabb().size.y > .06, "Groundcover must have real leaf height")
    RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
    var gpu_ms := 0.0
    for i in 30:
        await RenderingServer.frame_post_draw
        gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
    print("ANIME_GRASS instances=",count," varieties=",varieties," gpu_ms=",gpu_ms/30.0)
    var cam: Camera3D = scene.camera
    var old_size: float = cam.ortho_size
    cam.ortho_size = 8.0
    await settle(40)
    await capture(view, "grass_detail")
    cam.ortho_size = old_size
    await settle(40)
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = KEY_F7
    scene._unhandled_key_input(event)
    assert(not scene.art_direction.enabled and ground.material_override == original)
    assert(not grass.visible)
    scene._unhandled_key_input(event)
    assert(scene.art_direction.enabled and ground.material_override == painted)
    assert(grass.visible)
    var start: Vector3 = scene.player.position
    Input.action_press("move_down")
    await settle(40)
    Input.action_release("move_down")
    assert(scene.player.position.distance_to(start) > .5)
    for water in scene.waters:
        assert(water.simulation_enabled)
        var before: float = water._surface.material_override.get_shader_parameter("clock")
        await settle(4)
        assert(water._surface.material_override.get_shader_parameter("clock") > before)
        assert(water._surface.material_override.get_shader_parameter("anime_painted") == true)
    if "--export-editor-preview" in OS.get_cmdline_user_args():
        scene.player.position = Vector3(-9,1,24)
        scene.player.velocity = Vector3.ZERO
        await settle(60)
        await export_editor_preview(view)
    if not river_only:
        scene.player.position = Vector3(-42, 1, 10)
        scene.player.velocity = Vector3.ZERO
        await settle(90)
        await capture(view, "city_after")
        scene.art_direction.apply(false)
        await capture(view, "city_before")
    print("ANIME_ART_PASS: unchanged tree geometry, A/B restoration, F7, movement, live water; river_only=",river_only)
    scene.queue_free()
    await process_frame
    await process_frame
    # Let local Resource/Array references unwind before renderer shutdown.
    call_deferred("quit")
