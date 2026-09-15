extends Node3D

func _ready() -> void:
    var rig: Node = load("res://scenes/dev/gameplay_preview_rig.tscn").instantiate()
    var view: SubViewport = rig.get_node("Pixel/View")
    # Keep authored tree positions; use the same presentation as gameplay in Play.
    for child in get_children():
        remove_child(child)
        if child.name in ["Camera", "Environment", "Sun"]:
            child.free()
        else:
            view.add_child(child)
    add_child(rig)
    if "--capture-foliage" in OS.get_cmdline_user_args():
        await get_tree().create_timer(2.0).timeout
        await RenderingServer.frame_post_draw
        var path := "res://captures/foliage_study.png"
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
        var result := get_viewport().get_texture().get_image().save_png(path)
        print("FOLIAGE_CAPTURE ", result)
        get_tree().quit(result)
