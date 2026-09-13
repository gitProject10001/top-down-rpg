extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=load("res://scenes/dev/terrace_stairs_example.tscn").instantiate(); root.add_child(world)
	var h=world.get_node("CasaConTerrazza"); var terrace=h.attached_components()[0]
	assert(terrace.support_posts and terrace.exterior_stairs and terrace.validation_error().is_empty())
	h.rebuild()
	await physics_frame; await physics_frame
	var space := root.get_world_3d().direct_space_state
	var a: Vector3=terrace.to_global(Vector3(terrace.stair_center(),0.48,terrace.projection-0.3))
	var b: Vector3=terrace.to_global(Vector3(terrace.stair_center(),0.48,terrace.projection+0.3))
	assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b)).is_empty(),"Parapet must open for stairs")
	var packed := PackedScene.new(); assert(packed.pack(world)==OK)
	var copy=packed.instantiate(); var copied=copy.get_node("CasaConTerrazza").attached_components()[0]
	assert(copied.component_id==terrace.component_id and copied.exterior_stairs and copied.support_posts); copy.free()
	terrace.exterior_stairs=false; h.rebuild()
	await physics_frame; await physics_frame
	assert(not space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b)).is_empty(),"Removing stairs must restore parapet")
	terrace.exterior_stairs=true; terrace.ground_level=terrace.effective_elevation(); h.rebuild()
	assert(not terrace.validation_error().is_empty(),"Invalid ground height must be explicit")
	world.free(); print("TERRACE_PARAPET_RESTORE_SAVE_VALIDATION_OK"); quit()
