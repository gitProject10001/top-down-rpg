extends SceneTree
func _initialize() -> void:call_deferred("check")
func check() -> void:
    var scene=load("res://scenes/dev/river_study.tscn").instantiate()
    root.add_child(scene)
    for i in 3:await process_frame
    var river=scene.water
    assert(river.river_mode and river.boundary.size()==32 and river.flow_path.size()==16)
    assert(river._get_configuration_warnings().is_empty())
    assert(river.obstacles.size()==4)
    var obstacle: Vector4=river.obstacles[1]
    var center:=Vector2(obstacle.x,obstacle.y)
    assert(river.flow_at(center)==Vector2.ZERO)
    var before:=river.flow_at(Vector2(-10,-10)) as Vector2
    assert(before.is_finite() and before.length()>.1)
    for i in 20:
        var radial:=Vector2.from_angle(i*TAU/20)
        var velocity: Vector2=river.flow_at(center+radial*obstacle.z*1.01)
        assert(velocity.is_finite() and velocity.length()<=river.flow_speed*2.51)
    river.set_simulation(true)
    var field_id: int=river.wave_field.get_instance_id()
    assert(river.wave_field.flow_texture!=null)
    var rock=river.get_node("Rocks/Rock_1")
    rock.position.x+=1.5
    for i in 3:await process_frame
    assert(river.wave_field.get_instance_id()!=field_id,"Rock edits rebake simulation mask and flow")
    assert(absf(river.obstacles[1].x-center.x-1.5)<.01,"Moving the authored rock updates flow")
    assert(not rock.find_children("*","StaticBody3D",true,false).is_empty(),"Rocks retain builder collisions")
    var old: PackedVector2Array=river.boundary.duplicate()
    river.widths=PackedFloat32Array([7,8,7,9])
    for i in 3:await process_frame
    assert(river.boundary!=old,"Width edits rebuild river banks")
    print("RIVER_PASS: curve, widths, bounded flow, rock exclusion, movement sync, collisions")
    quit()
