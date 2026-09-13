extends SceneTree
func _initialize() -> void: call_deferred("run")
func ray(x: float,z: float) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,3.1,z),Vector3(x,2.6,z)))
func run() -> void:
	var scene=load("res://scenes/dev/tower_interior_example.tscn").instantiate(); root.add_child(scene)
	var tower=scene.get_node("TorreOttagonale"); var plan=tower.get_node("InteriorPlan")
	plan.rebuild(); await physics_frame; await physics_frame
	assert(ray(0,0).is_empty(),"Upper slab leaves staircase opening")
	assert(not ray(1.4,0).is_empty(),"Upper slab is solid outside staircase")
	assert(ray(2.8,2.8).is_empty(),"Interior slab follows clipped polygon corner")
	var stairs=plan.get_node("PianoTerra/ScalaPrimoPiano")
	assert(stairs._get_configuration_warnings().is_empty())
	stairs.dimensions.y=2.4; assert(not stairs._get_configuration_warnings().is_empty()); stairs.dimensions.y=2.8
	stairs.position.x=4.0; assert(not stairs._get_configuration_warnings().is_empty())
	stairs.position.x=0.9; stairs.rebuild(); plan.rebuild(); await physics_frame; await physics_frame
	assert(not ray(0,0).is_empty(),"Moving stairs restores former floor opening")
	assert(ray(0.9,0).is_empty(),"Opening follows authored staircase")
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("TorreOttagonale/InteriorPlan")
	assert(saved.levels().size()==2 and is_equal_approx(saved.get_node("PianoTerra/ScalaPrimoPiano").position.x,0.9))
	assert(saved.get_node("PrimoPiano").get_meta("floor_id")=="tower_upper")
	copy.free(); scene.free(); print("TOWER_INTERIOR_POLYGON_FLOORS_MOVING_HOLE_SAVE_OK"); quit()
