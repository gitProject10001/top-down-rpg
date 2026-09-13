extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); root.add_child(wall)
	wall.gate_open=true; wall.rebuild(); await physics_frame; await physics_frame
	var space=root.get_world_3d().direct_space_state
	var passage=PhysicsRayQueryParameters3D.create(Vector3(0,1,2),Vector3(0,1,-2))
	assert(space.intersect_ray(passage).is_empty(),"Gate opening crosses full wall thickness")
	var above=PhysicsRayQueryParameters3D.create(Vector3(0,3.7,2),Vector3(0,3.7,-2))
	assert(not space.intersect_ray(above).is_empty(),"Lintel remains solid")
	wall.gate_offset=0.5; wall.width=14.0; wall.rebuild(); await physics_frame; await physics_frame
	assert(not space.intersect_ray(passage).is_empty(),"Moving gate restores previous wall")
	var moved=PhysicsRayQueryParameters3D.create(Vector3(3.5,1,2),Vector3(3.5,1,-2))
	assert(space.intersect_ray(moved).is_empty())
	var packed := PackedScene.new(); assert(packed.pack(wall)==OK)
	var copy=packed.instantiate(); assert(copy.gate_open and copy.gate_offset==0.5 and copy.width==14.0); copy.free()
	wall.gate_enabled=false; wall.rebuild(); await physics_frame; await physics_frame
	assert(not space.intersect_ray(moved).is_empty(),"Disabling gate produces solid curtain")
	wall.free(); print("CURTAIN_PASSAGE_MOVE_DISABLE_SAVE_OK"); quit()
