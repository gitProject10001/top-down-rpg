extends SceneTree
## Refresh the lightweight preview rig from the current main scene, without running it.
func _initialize() -> void:
    var source: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
    source.name = "GameplayPreviewRig"
    var view := source.get_node("Pixel/View")
    var keep := ["WorldEnvironment", "Sun", "IsoCam", "PixelSnap", "SoftSkyFill", "VillageCharacterPalette", "Player"]
    for child in view.get_children():
        if child.name not in keep:
            view.remove_child(child)
            child.free()
    view.get_node("Player").position = Vector3(0, 0.1, 3)
    view.get_node("PixelSnap").targets = [NodePath("../Player")] as Array[NodePath]
    var packed := PackedScene.new()
    assert(packed.pack(source) == OK)
    assert(ResourceSaver.save(packed, "res://scenes/dev/gameplay_preview_rig.tscn") == OK)
    source.free()
    print("GAMEPLAY_PREVIEW_RIG_SAVED")
    quit()
