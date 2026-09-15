extends SceneTree
func _initialize() -> void:
    var scene:=Node3D.new()
    scene.name="RiverStudy"
    scene.set_script(load("res://scripts/village/water_study.gd"))
    scene.water_path=NodePath("River")
    scene.spawn_position=Vector3(-3,1,3)
    scene.capture_position=Vector3(2,.7,1)
    scene.capture_file="res://captures/river_study.png"
    var river:=Node3D.new()
    river.set_script(load("res://addons/water_builder/river.gd"))
    river.name="River";scene.add_child(river);river.owner=scene
    river.flow_speed=.9
    river.widths=PackedFloat32Array([5,7,5,6,8])
    var guide:=Path3D.new();guide.name="FlowGuide"
    guide.curve=Curve3D.new()
    var points: Array[Vector3]=[Vector3(-13,0,-13),Vector3(-7,0,-6),Vector3(1,0,-3),Vector3(4,0,4),Vector3(13,0,11)]
    for i in points.size():
        var tangent: Vector3=(points[mini(points.size()-1,i+1)]-points[maxi(0,i-1)])*.15
        guide.curve.add_point(points[i],-tangent,tangent)
    river.add_child(guide);guide.owner=scene
    var rocks:=Node3D.new();rocks.name="Rocks";river.add_child(rocks);rocks.owner=scene
    var positions: Array[Vector3]=[Vector3(-6,-.38,-5.6),Vector3(.2,-.38,-3.0),Vector3(3.8,-.38,2.9),Vector3(5.7,-.38,6.0)]
    for i in positions.size():
        var rock:=Node3D.new();rock.name="Rock_%d"%i
        rock.set_script(load("res://addons/rock_builder/rock.gd"))
        rock.rock_seed=31+i*7
        rock.dimensions=Vector3(1.8+i*.1,1.3+i*.2,1.7)
        rock.position=positions[i]
        rocks.add_child(rock);rock.owner=scene
    var packed:=PackedScene.new();assert(packed.pack(scene)==OK)
    assert(ResourceSaver.save(packed,"res://scenes/dev/river_study.tscn")==OK)
    scene.free()
    print("RIVER_STUDY_SAVED")
    quit()
