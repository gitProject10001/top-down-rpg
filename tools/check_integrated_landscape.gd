extends SceneTree
func _initialize() -> void:call_deferred("check")
func check() -> void:
    var scene=load("res://scenes/dev/integrated_landscape.tscn").instantiate();root.add_child(scene)
    for i in 30:await physics_frame
    var view=scene.get_node("GameplayPreviewRig/Pixel/View")
    var castle=view.get_node("CittaMurata")
    for wall in castle.curtains():assert(wall.connection_error().is_empty(),wall.connection_error())
    assert(castle.curtains().size()==8)
    assert(scene.waters.size()==2)
    for water in scene.waters:assert(water.simulation_enabled and water.wave_field!=null)
    assert(view.get_node("Boschi").get_child_count()==91)
    for target in [Vector3(-42,0,-4),Vector3(-42,0,10),Vector3(-22,0,16),Vector3(-5,0,22),Vector3(12,0,23)]:
        for frame in 550:
            var direction: Vector3=target-scene.player.position;direction.y=0
            if direction.length()<.6:break
            var raw:=direction.normalized().rotated(Vector3.UP,-scene.camera.global_rotation.y)
            for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
                if pair[1]>0:Input.action_press(pair[0],pair[1])
                else:Input.action_release(pair[0])
            await physics_frame
        for action in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)
        var distance: Vector2=Vector2(scene.player.position.x-target.x,scene.player.position.z-target.z)
        assert(distance.length()<1,"Route blocked at "+str(scene.player.position)+" target "+str(target))
    assert(scene.player.is_on_floor())
    scene.toggle_overview();assert(scene.overview and scene.camera.size==145)
    scene.toggle_overview();assert(not scene.overview)
    print("INTEGRATED_PASS 8 curtains, 2 simulated waters, 91 trees, city-ford-village movement")
    scene.queue_free();await process_frame;await process_frame
    quit()
