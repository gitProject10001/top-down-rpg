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
    var house=view.get_node("CasaCitta_00")
    var plan=house.get_node("InteriorPlan")
    assert(plan.levels().size()==1 and plan.level_records(0).size()>2)
    scene.player.position=Vector3(-40,1,-15.6);scene.player.velocity=Vector3.ZERO
    for i in 40:await physics_frame
    if not is_instance_valid(scene.nearest_door):
        print("INTEGRATED_DOOR_DIAGNOSTIC player=",scene.player.global_position," state=",scene.player.state_name()," house=",house.global_position)
        for door in house.find_children("*","AnimatableBody3D",true,false): print("DOOR ",door.get_path()," at=",door.global_position)
    assert(is_instance_valid(scene.nearest_door),"Exterior door can be selected")
    var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_E
    scene._unhandled_key_input(event)
    for i in 30:await physics_frame
    for i in 80:
        var raw:=Vector3.FORWARD.rotated(Vector3.UP,-scene.camera.global_rotation.y)
        for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
            if pair[1]>0:Input.action_press(pair[0],pair[1])
            else:Input.action_release(pair[0])
        await physics_frame
        if scene.player.position.z<-17.5:break
    for action in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)
    assert(scene.player.position.z<-17.5,"Walk through opened house door "+str(scene.player.position)+" door="+str(scene.nearest_door))
    assert(scene.interior_states[plan.get_instance_id()].x==1,"Interior cutaway activated")
    print("INTERIOR_PASS entry through E door and cutaway")

    scene.toggle_overview();assert(scene.overview and scene.camera.size==145)
    scene.toggle_overview();assert(not scene.overview)
    print("INTEGRATED_PASS 8 curtains, 2 simulated waters, 91 trees, city-ford-village movement")
    scene.queue_free();await process_frame;await process_frame
    quit()
