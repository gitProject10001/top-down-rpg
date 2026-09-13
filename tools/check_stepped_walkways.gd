extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create(); root.add_child(group)
	for node in group.find_children("*","Node",true,false): node.owner=group
	var wall=group.curtains()[0]; var target=group.get_node("TorreEst")
	wall.gate_enabled=false; wall.allow_sloped_walkway=true; target.wall_height=9.6; await settle()
	assert(not wall.connection_error().is_empty(),"Four-metre rise exceeds ramp limit")
	wall.walkway_profile=1; await settle(); assert(wall.connection_error().is_empty())
	assert(wall._generated.get_node("Roof").mesh.get_surface_count()>wall._walkway_collision.get_surface_count(),"Rendered treads are separate from smooth movement collision")
	var space=root.get_world_3d().direct_space_state
	for item in [[4.2,5.78],[8.0,7.78],[11.8,9.78]]:
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(item[0],11,0),Vector3(item[0],4,0)))
		assert(not hit.is_empty() and absf(hit.position.y-item[1])<0.025,"Flat landings and continuous middle collision")
	var packed := PackedScene.new(); assert(packed.pack(group)==OK)
	var copy=packed.instantiate(); assert(copy.curtains()[0].walkway_profile==1); copy.free()
	target.position.x=12; await settle(); assert(not wall.connection_error().is_empty(),"Short run rejected")
	target.position.x=16; target.wall_height=5.6; await settle(); assert(is_zero_approx(wall._slope_rise))
	assert(wall._generated.get_node("Roof").mesh==wall._walkway_collision,"Level roofs need no stairs")
	group.free(); print("STEPPED_WALKWAY_LANDINGS_COLLISION_LIMIT_SAVE_OK"); quit()
