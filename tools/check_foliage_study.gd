extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func check() -> void:
    for kind in ["broadleaf", "pine"]:
        var tree = load("res://scenes/props/study_%s.tscn" % kind).instantiate()
        root.add_child(tree)
        var meshes = tree.find_children("*", "MeshInstance3D")
        assert(meshes.size() == 2, "Each GLB must contain only its own branches and leaves")
        var foliage_found := false
        var triangles := 0
        for mesh in meshes:
            for i in mesh.mesh.get_surface_count():
                var arrays = mesh.mesh.surface_get_arrays(i)
                triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
                if str(mesh.name).begins_with("Leaves"):
                    foliage_found = true
                    assert(mesh.material_override is ShaderMaterial)
                    assert(arrays[Mesh.ARRAY_COLOR].size() == arrays[Mesh.ARRAY_VERTEX].size())
                    var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
                    assert(normals.size() > 100)
                    assert(normals[0].distance_to(normals[40]) > 0.01, "Transferred normals must vary")
        assert(foliage_found)
        assert(triangles < 12000, "Prototype geometry budget")
        assert(tree.get_node("TrunkCollision/Shape").shape is CylinderShape3D)
        print("FOLIAGE_PASS ",kind," triangles=",triangles)
        tree.queue_free()
    quit()
