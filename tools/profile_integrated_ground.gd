extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var source=load("res://scenes/dev/integrated_landscape.tscn").instantiate()
    var ground=source.get_node("TerrenoComposto/Superficie");ground.get_parent().remove_child(ground);source.free()
    var view:=SubViewport.new();view.size=Vector2i(1400,900);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
    view.add_child(ground)
    var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-60,30,0);view.add_child(sun)
    var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80;view.add_child(camera);camera.position=Vector3(0,80,25);camera.look_at(Vector3.ZERO)
    RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
    var original: Material=ground.material_override
    for mode in 2:
        if mode==1:ground.material_override=StandardMaterial3D.new()
        for i in 20:await process_frame
        var gpu:=0.0;var cpu:=0.0
        for i in 60:
            await RenderingServer.frame_post_draw
            gpu+=RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
            cpu+=RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid())
        print("GROUND_PROFILE mode=",mode," gpu_ms=",gpu/60," render_cpu_ms=",cpu/60)
    view.queue_free();await process_frame;quit()
