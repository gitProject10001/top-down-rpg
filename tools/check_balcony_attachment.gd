extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Balcony=preload("res://addons/house_builder/balcony.gd")
func _initialize() -> void: call_deferred("run")
func ray(a: Vector3,b: Vector3) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b))
func run() -> void:
	var h := House.new(); h.width=6; h.depth=6; h.wall_height=5.5
	h.openings=[{"kind":"window","wall":2,"u":0.0,"y":1.5}]
	root.add_child(h)
	var container := Node3D.new(); container.name="Components"; h.add_child(container); container.owner=h
	var b := Balcony.new(); b.elevation=2.8; b.door_open=true; container.add_child(b); b.owner=h
	h.rebuild(); assert(b.validation_error().is_empty())
	var id := b.component_id; assert(not id.is_empty())
	assert(h.all_openings().size()==2 and h.openings.size()==1)
	await physics_frame; await physics_frame
	assert(ray(Vector3(0,3.8,3.4),Vector3(0,3.8,2.5)).is_empty(),"Door must cut actual wall collision")
	assert(not ray(Vector3(1.1,3.8,3.4),Vector3(1.1,3.8,2.5)).is_empty(),"Wall beside door must remain")
	assert(not ray(Vector3(0,3.2,4),Vector3(0,2.4,4)).is_empty(),"Balcony must support actor")
	h.width=8; b.along=0.3; h.rebuild(); assert(is_equal_approx(b.position.x,1.2))
	var saved := PackedScene.new(); assert(saved.pack(h)==OK); assert(ResourceSaver.save(saved,"user://balcony_test.tscn")==OK)
	var restored=load("user://balcony_test.tscn").instantiate(); root.add_child(restored)
	assert(restored.attached_components()[0].component_id==id); assert(restored.all_openings().size()==2)
	restored.free()
	container.remove_child(b); h.rebuild(); assert(h.all_openings().size()==1)
	await physics_frame; await physics_frame
	assert(not ray(Vector3(1.2,3.8,3.4),Vector3(1.2,3.8,2.5)).is_empty(),"Removal must close wall")
	container.add_child(b); b.owner=h; h.rebuild(); assert(b.component_id==id and h.all_openings().size()==2)
	b.elevation=5; h.rebuild(); assert(not b.validation_error().is_empty() and h.all_openings().size()==1)
	b.elevation=2.8; b.host_id="main/right"; b.along=0; h.rebuild(); assert(b.validation_error().is_empty())
	var conflict: Dictionary=b.opening_record(); conflict.erase("component_id"); h.openings.append(conflict); h.rebuild()
	assert(not b.validation_error().is_empty())
	b.create_door=false; h.rebuild(); assert(b.validation_error().is_empty() and h.all_openings().size()==2)
	# Bind an existing manual door and floor by identity, then rename/reorder.
	var plan=preload("res://addons/house_builder/plan.gd").new(); plan.name="InteriorPlan"; plan.floor_height=2.8
	h.add_child(plan); plan.owner=h
	for i in 2:
		var level := Node3D.new(); level.name="Floor%d"%i; level.set_meta("floor_id","test_floor_%d"%i); plan.add_child(level); level.owner=h
	conflict.opening_id="manual_access"; conflict.floor_id="test_floor_1"
	h.openings=[conflict,{"kind":"window","wall":0,"y":1.4}]
	b.door_id="manual_access"; b.floor_id="test_floor_1"; b.create_door=true
	plan.rebuild(); h.rebuild(); assert(b.validation_error().is_empty() and h.all_openings().size()==2)
	plan.levels()[1].name="CameraSuperiore"; plan.floor_height=3.2; plan.rebuild(); h.rebuild()
	assert(is_equal_approx(b.position.y,3.2) and is_equal_approx(h.opening_floor_y(h.openings[0]),3.2))
	h.openings.reverse(); h.openings[1].u=0.25; h.rebuild(); assert(is_equal_approx(b.effective_along(),0.25))
	var linked_save := PackedScene.new(); assert(linked_save.pack(h)==OK)
	var linked_copy=linked_save.instantiate(); root.add_child(linked_copy)
	assert(linked_copy.attached_components()[0].door_id=="manual_access" and is_equal_approx(linked_copy.attached_components()[0].effective_elevation(),3.2)); linked_copy.free()
	var upper=plan.levels()[1]; plan.remove_child(upper); h.rebuild(); assert("piano" in b.validation_error())
	plan.add_child(upper); plan.rebuild(); h.rebuild(); assert(b.validation_error().is_empty())
	h.openings.remove_at(1); h.rebuild(); assert("porta" in b.validation_error())
	h.openings.append(conflict); h.rebuild(); assert(b.validation_error().is_empty())
	print("BALCONY_FLOOR_DOOR_IDS_RENAME_REORDER_DELETE_SAVE_OK")
	container.remove_child(b); b.free(); assert(h.openings.size()==2,"Manual/shared access must survive removal")
	h.free(); print("BALCONY_OPENING_COLLISION_ATTACH_REMOVE_SAVE_MANUAL_OK"); quit()
