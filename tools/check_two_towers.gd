extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create(); root.add_child(group)
	for node in group.find_children("*","Node",true,false): node.owner=group
	await settle()
	var wall=group.curtains()[0]; var east=group.get_node("TorreEst"); var west=group.primary_tower()
	assert(wall.connection_error().is_empty() and is_equal_approx(wall.width,8.2))
	var space=root.get_world_3d().direct_space_state
	var gap=PhysicsRayQueryParameters3D.create(Vector3(11,6,0),Vector3(13,6,0))
	assert(space.intersect_ray(gap).is_empty(),"Destination parapet and curtain end open")
	east.position.x=18; await settle(); assert(is_equal_approx(wall.width,10.2))
	west.position.x=1; await settle(); assert(is_equal_approx(wall.width,9.2),"Moving source also updates link")
	east.position.z=1; await settle(); assert(not wall.connection_error().is_empty(),"Misalignment visible as error")
	east.position.z=0; await settle(); assert(wall.connection_error().is_empty())
	var packed := PackedScene.new(); assert(packed.pack(group)==OK)
	var copy=packed.instantiate(); assert(copy.curtains()[0].destination()==copy.get_node("TorreEst")); copy.free()
	wall.target_tower=NodePath(); await settle()
	var spans: Array[Vector2]=[Vector2(-1,1)]
	assert(east.connection_spans(6,spans).size()==1,"Removing destination closes its parapet")
	group.free(); print("TWO_TOWERS_ENDPOINTS_MOVE_INVALIDATE_SAVE_OK"); quit()
