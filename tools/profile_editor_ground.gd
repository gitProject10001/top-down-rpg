extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    await create_timer(4).timeout
    while EditorInterface.get_resource_filesystem().is_scanning():await process_frame
    EditorInterface.open_scene_from_path("res://scenes/dev/integrated_landscape.tscn")
    await create_timer(5).timeout
    var scene:=EditorInterface.get_edited_scene_root()
    print("EDITOR_SCENE ",scene.scene_file_path)
    var ground:=scene.get_node("TerrenoComposto")
    for mode in 2:
        EditorInterface.get_selection().clear()
        var target: Node=ground if mode==0 else ground.get_node("Superficie")
        EditorInterface.get_selection().add_node(target);EditorInterface.edit_node(target)
        for i in 30:await process_frame
        var begin:=Time.get_ticks_usec()
        for i in 90:await process_frame
        print("EDITOR_SELECTION ",mode," frame_ms=",(Time.get_ticks_usec()-begin)/90000.0)
    quit()
