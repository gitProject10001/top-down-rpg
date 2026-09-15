extends SceneTree

func _initialize() -> void:
    call_deferred("check")

func walk(player: CharacterBody3D, camera: Camera3D, target: Vector3) -> void:
    for frame in 150:
        var direction:=target-player.position
        direction.y=0
        if direction.length()<.25:break
        var raw:=direction.normalized().rotated(Vector3.UP,-camera.global_rotation.y)
        for pair in [["move_left",-raw.x],["move_right",raw.x],["move_up",-raw.z],["move_down",raw.z]]:
            if pair[1]>0:Input.action_press(pair[0],pair[1])
            else:Input.action_release(pair[0])
        await physics_frame
    for action in ["move_left","move_right","move_up","move_down"]:Input.action_release(action)
    for i in 20:await physics_frame

func check() -> void:
    var scene=load("res://scenes/dev/water_study.tscn").instantiate()
    root.add_child(scene)
    var water=scene.water
    var player: CharacterBody3D=scene.player
    var camera=scene.get_node("GameplayPreviewRig/Pixel/View/IsoCam")
    assert(water._get_configuration_warnings().is_empty())
    assert(water.contains_point(Vector2(-3,2)))
    assert(not water.contains_point(Vector2(-3,7)))
    assert(water.bed_height(Vector2(-3,2))<-.3)
    for i in 30:await physics_frame
    await walk(player,camera,Vector3(-3,0,2))
    assert(player.is_on_floor() and player.position.z<2.5,"Enter lake on the shallow bed")
    assert(water._rings[0].w>0,"Walking produces local rings")
    assert(water._wakes[0].w>0 and water._directions[0].length()>.9,"Motion creates directional wakes")
    assert(water._spray.multimesh.instance_count==48,"Spray has a fixed budget")
    var wake_count: int=water._next_wake
    water.disturb(player.global_position,Vector3.ZERO)
    water.disturb(Vector3(-20,0,20),Vector3(3,0,0))
    assert(water._next_wake==wake_count,"Stationary player and dry land do not emit wakes")
    var count: int=water._next_ring
    water.ripple(Vector3(-20,0,20))
    assert(water._next_ring==count,"Dry land does not produce rings")
    for key in [KEY_F,KEY_V]:
        var event:=InputEventKey.new();event.pressed=true;event.keycode=key
        scene._unhandled_key_input(event)
        await process_frame
    assert(water.debug_flow and water.vortex_strength>.0)
    await walk(player,camera,Vector3(-3,0,7))
    assert(player.is_on_floor() and player.position.z>6.5,"Exit lake across bank")
    print("WATER_PASS: lake entry/exit, collision, ripples, flow debug and vortex")
    quit()
