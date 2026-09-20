extends SceneTree
## Checks deterministic, bounded branch-aligned cards and renders 8 angles x 3
## orthographic sizes for both original tree species. No source asset is edited.
const BUILDER = preload("res://scripts/village/canopy_shading.gd")
const SHADER = preload("res://shaders/pixelart/anime_canopy.gdshader")
var view: SubViewport

func _initialize() -> void:
    call_deferred("run")

func settle(frames: int = 5) -> void:
    for frame in frames:
        await process_frame

func run() -> void:
    view = SubViewport.new()
    view.size = Vector2i(320, 360)
    view.own_world_3d = true
    view.msaa_3d = Viewport.MSAA_4X
    view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(view)
    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color(.12, .17, .19)
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color(.53, .72, .77)
    env.environment.ambient_light_energy = .70
    view.add_child(env)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-48, -32, 0)
    light.light_color = Color(1, .94, .79)
    light.light_energy = 1.2
    light.shadow_enabled = true
    light.light_angular_distance = 1.8
    view.add_child(light)
    var fill := DirectionalLight3D.new()
    fill.rotation_degrees = Vector3(-30, 150, 0)
    fill.light_color = Color(.56, .72, .83)
    fill.light_energy = .3
    view.add_child(fill)
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(80, 80)
    floor_mesh.mesh = plane
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color(.31, .34, .24)
    floor_material.roughness = 1.0
    floor_mesh.material_override = floor_material
    view.add_child(floor_mesh)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    view.add_child(camera)
    var builder = BUILDER.new()
    var texture: Texture2D = load("res://assets/textures/anime_painted/foliage_sprays.png")
    assert(texture != null)
    var atlas_image := texture.get_image()
    assert(atlas_image.detect_alpha() != Image.ALPHA_NONE, "Foliage requires true alpha, not a painted background")
    var cards_total := 0
    for species in ["broadleaf", "pine"]:
        var tree: Node3D = load("res://assets/models/foliage_study/" + species + ".glb").instantiate()
        view.add_child(tree)
        var leaves: MeshInstance3D
        var trunks: Array[Dictionary] = []
        for node in tree.find_children("*", "MeshInstance3D", true, false):
            if str(node.name).to_lower().contains("leaves"):
                leaves = node
            else:
                trunks.append({"node": node, "mesh": node.mesh, "transform": node.transform})
        assert(leaves != null)
        var original: Mesh = leaves.mesh
        var original_arrays := original.surface_get_arrays(0)
        var original_vertices: PackedVector3Array = original_arrays[Mesh.ARRAY_VERTEX]
        var painted: ArrayMesh = builder.for_mesh(original, species)
        assert(builder.for_mesh(original, species) == painted, "Repeated requests reuse the same mesh")
        var independent: ArrayMesh = BUILDER.new().for_mesh(original, species)
        var arrays := painted.surface_get_arrays(0)
        assert(arrays[Mesh.ARRAY_VERTEX] == independent.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
        assert(original.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original_vertices)
        assert(original.get_aabb().grow(.001).encloses(painted.get_aabb()))
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
        assert(vertices.size() % 6 == 0)
        assert(arrays[Mesh.ARRAY_INDEX].size() == vertices.size() * 2)
        var shapes: PackedInt32Array = painted.get_meta("shape_counts")
        for count in shapes:
            assert(count > 0)
        for i in vertices.size():
            assert(normals[i].is_finite() and absf(normals[i].length() - 1.0) < .002)
            assert(uvs[i].x > 0.0 and uvs[i].x < 1.0 and uvs[i].y > 0.0 and uvs[i].y < 1.0)
            assert(colors[i].b == 0.0 if i % 6 < 3 else colors[i].b == 1.0, "Wind is anchored at each spray base")
        for card in vertices.size() / 6:
            var base := card * 6
            var midpoint := (vertices[base] + vertices[base + 2]) * .5
            assert(midpoint.distance_to(vertices[base + 1]) > .005, "The spray must actually fold")
        leaves.mesh = painted
        var material := ShaderMaterial.new()
        material.shader = SHADER
        material.set_shader_parameter("leaf_painting", texture)
        material.set_shader_parameter("wind_strength", 0.0)
        leaves.material_override = material
        var height := original.get_aabb().end.y
        var focus := Vector3(0, height * .48, 0)
        var sheet := Image.create(view.size.x * 8, view.size.y * 3, false, Image.FORMAT_RGBA8)
        for distance in 3:
            camera.size = height * [1.15, 1.65, 2.30][distance]
            for angle in 8:
                var azimuth := TAU * angle / 8.0
                camera.position = focus + Vector3(cos(azimuth), .85, sin(azimuth)) * 20.0
                camera.look_at(focus)
                await settle()
                await RenderingServer.frame_post_draw
                for trunk in trunks:
                    assert(trunk.node.mesh == trunk.mesh and trunk.node.transform == trunk.transform)
                assert(leaves.mesh == painted and leaves.transform == Transform3D.IDENTITY,
                    "Near foliage is world-fixed, never rotated to the camera")
                var screenshot := view.get_texture().get_image()
                screenshot.convert(Image.FORMAT_RGBA8)
                sheet.blit_rect(screenshot, Rect2i(Vector2i.ZERO, view.size),
                    Vector2i(view.size.x * angle, view.size.y * distance))
        assert(sheet.save_png("res://captures/anime_tree_" + species + "_8x3.png") == OK)
        cards_total += vertices.size() / 6
        print("TREE_CHECK ", species, " cards=", vertices.size() / 6, " shapes=", shapes,
            " source_bounds=", original.get_aabb(), " result_bounds=", painted.get_aabb())
        tree.queue_free()
        await process_frame
    print("ANIME_TREES_PASS: ", cards_total, " folded sprays; 48 views; four original atlas cells; deterministic; original trunks and envelope retained")
    view.queue_free()
    await process_frame
    quit()
