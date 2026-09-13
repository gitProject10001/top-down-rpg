extends SceneTree
func _initialize() -> void: call_deferred("run")
func seam_ray() -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2.4,1.2,-2),Vector3(3.6,1.2,-2)))
func run() -> void:
	var world=load("res://scenes/dev/multi_volume_example.tscn").instantiate(); root.add_child(world)
	var host=world.get_node("CasaComposta"); var body=host.authored_volumes()[0]; host.authored_volumes()[1].junction_mode=0
	host.rebuild(); assert(body.volume_error().is_empty())
	await physics_frame; await physics_frame
	assert(seam_ray().is_empty(),"Both wall faces must be removed at the junction")
	body.junction_mode=1; host.rebuild()
	await physics_frame; await physics_frame
	assert(not seam_ray().is_empty(),"Closed derived door blocks the seam")
	assert(host.all_openings().size()==host.openings.size()+1)
	body.junction_open=true; host.rebuild()
	await physics_frame; await physics_frame
	assert(seam_ray().is_empty(),"Open derived door clears the passage")
	var side_ray=PhysicsRayQueryParameters3D.create(Vector3(2.4,1.2,-3),Vector3(3.6,1.2,-3))
	assert(not root.get_world_3d().direct_space_state.intersect_ray(side_ray).is_empty(),"Partition remains beside the doorway")
	var door_pack := PackedScene.new(); assert(door_pack.pack(world)==OK)
	var saved=door_pack.instantiate(); var saved_body=saved.get_node("CasaComposta").authored_volumes()[0]
	assert(saved_body.junction_mode==1 and saved_body.junction_open); saved.free()
	body.junction_width=10; host.rebuild(); assert(not body.volume_error().is_empty())
	assert(host.all_openings().size()==host.openings.size(),"Invalid doorway is not generated")
	body.junction_width=1.2; body.junction_mode=0; host.rebuild()
	var lot=preload("res://addons/village_builder/lot.gd").new(); var clone=host.duplicate(); clone.name="Edificio"; lot.add_child(clone)
	var polygon: PackedVector2Array=lot.polygon(); var max_x := -INF
	for point in polygon: max_x=maxf(max_x,point.x)
	assert(max_x>6,"Village footprint includes annexes"); lot.free()
	var main_dimensions=host.dimensions(); var openings=body.openings.duplicate(true); var id=body.volume_id
	body.depth+=0.5; host.rebuild(); assert(host.dimensions()==main_dimensions and body.openings==openings)
	body.attached=false; host.rebuild()
	await physics_frame; await physics_frame
	assert(not seam_ray().is_empty(),"Detaching must restore main wall")
	body.position.x+=2; var free_pose=body.transform; host.rebuild(); assert(body.transform==free_pose)
	body.attached=true; host.rebuild(); assert(body.transform!=free_pose)
	var packed := PackedScene.new(); assert(packed.pack(world)==OK)
	var copy=packed.instantiate(); var restored=copy.get_node("CasaComposta").authored_volumes()[0]
	assert(restored.volume_id==id and restored.openings==openings and restored.depth==body.depth); copy.free()
	body.roof_height=5; host.rebuild(); assert(not body.volume_error().is_empty())
	await physics_frame; await physics_frame
	assert(not seam_ray().is_empty(),"Invalid annex must not cut main wall")
	var parent=body.get_parent(); parent.remove_child(body); body.free(); host.rebuild()
	assert(host.authored_volumes().size()==1)
	world.free(); print("MULTI_VOLUME_SEAM_DETACH_INDEPENDENT_SAVE_INVALID_OK"); quit()
