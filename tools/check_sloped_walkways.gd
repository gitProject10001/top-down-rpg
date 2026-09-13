extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create(); root.add_child(group)
	for node in group.find_children("*","Node",true,false): node.owner=group
	var wall=group.curtains()[0]; var target=group.get_node("TorreEst")
	wall.gate_enabled=false; target.wall_height=6.8; await settle()
	assert(not wall.connection_error().is_empty(),"Different heights require explicit opt-in")
	wall.allow_sloped_walkway=true; await settle(); assert(wall.connection_error().is_empty())
	var space=root.get_world_3d().direct_space_state
	for item in [[4.2,5.81],[8.0,6.38],[11.8,6.95]]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(item[0],8,0),Vector3(item[0],4,0)))
		assert(not hit.is_empty() and absf(hit.position.y-item[1])<0.04,"Roof collision follows slope")
	wall.gate_enabled=true; await settle(); assert(not wall.connection_error().is_empty())
	wall.gate_enabled=false; target.wall_height=10; await settle(); assert(not wall.connection_error().is_empty(),"Excessive slope rejected")
	target.wall_height=6.8; await settle(); assert(wall.connection_error().is_empty())
	var packed := PackedScene.new(); assert(packed.pack(group)==OK)
	var copy=packed.instantiate(); assert(copy.curtains()[0].allow_sloped_walkway); copy.free()
	target.wall_height=5.6; await settle(); assert(is_zero_approx(wall._slope_rise))
	group.free(); print("SLOPED_WALKWAY_COLLISION_LIMITS_RESET_SAVE_OK"); quit()
