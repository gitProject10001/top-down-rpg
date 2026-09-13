extends SceneTree
func _initialize() -> void: call_deferred("run")
func roof_ray(x: float) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,6.1,0),Vector3(x,5.4,0)))
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var scene=load("res://scenes/dev/tower_roof_stair_example.tscn").instantiate(); root.add_child(scene)
	var tower=scene.get_node("TorreOttagonale"); var plan=tower.get_node("InteriorPlan")
	await settle()
	var stairs=plan.get_node("PrimoPiano/ScalaTetto")
	assert(is_equal_approx(stairs.stair_height(),2.93))
	assert(roof_ray(1.5).is_empty(),"Roof opening clears collision above stairs")
	assert(not roof_ray(-1.5).is_empty(),"Other roof remains solid")
	stairs.position.x=0.4; await settle()
	assert(roof_ray(0.4).is_empty() and not roof_ray(1.5).is_empty(),"Manual move updates roof opening")
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("TorreOttagonale/InteriorPlan/PrimoPiano/ScalaTetto")
	assert(saved.roof_exit and is_equal_approx(saved.position.x,0.4)); copy.free()
	stairs.roof_exit=false; await settle()
	assert(not roof_ray(0.4).is_empty(),"Disabling roof connection restores slab")
	stairs.roof_exit=true; await settle(); assert(roof_ray(0.4).is_empty())
	stairs.get_parent().remove_child(stairs); stairs.free(); await settle()
	assert(not roof_ray(0.4).is_empty(),"Deleting stair restores slab")
	scene.free(); print("TOWER_ROOF_STAIR_MOVE_DISABLE_DELETE_SAVE_OK"); quit()
