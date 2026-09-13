extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create_enclosure(); root.add_child(group)
	for node in group.find_children("*","Node",true,false): node.owner=group
	await settle()
	assert(group.get_child_count()==4 and group.curtains().size()==4)
	var incoming := {}; var gates := 0
	for wall in group.curtains():
		assert(wall.connection_error().is_empty())
		assert(not incoming.has(wall.destination())); incoming[wall.destination()]=true
		if wall.gate_enabled: gates+=1
	assert(incoming.size()==4 and gates==1,"Closed four-tower graph with one entrance")
	var space=root.get_world_3d().direct_space_state
	for endpoint in [Vector3(8,1,-25),Vector3(25,1,-8),Vector3(-10,1,-8)]:
		assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(8,1,-8),endpoint)).is_empty(),"Non-gate sides enclose courtyard")
	var gate_ray=PhysicsRayQueryParameters3D.create(Vector3(8,1,-8),Vector3(8,1,8))
	assert(not space.intersect_ray(gate_ray).is_empty())
	group.get_node("TorreOvest/Cortina").gate_open=true; await settle()
	assert(space.intersect_ray(gate_ray).is_empty(),"Only opened front gate clears courtyard exit")
	group.get_node("TorreEst").position.x=18; group.get_node("TorreNordEst").position.x=18; await settle()
	for wall in group.curtains(): assert(wall.connection_error().is_empty())
	assert(is_equal_approx(group.get_node("TorreOvest/Cortina").width,10.2))
	assert(is_equal_approx(group.get_node("TorreNordEst/Cortina").width,10.2))
	var packed := PackedScene.new(); assert(packed.pack(group)==OK)
	var copy=packed.instantiate(); assert(copy.courtyard_entry and copy.curtains().size()==4)
	for wall in copy.curtains(): assert(wall.destination()!=null)
	copy.free(); group.free(); print("ENCLOSURE_GRAPH_GATE_COLLISION_RESIZE_SAVE_OK"); quit()
