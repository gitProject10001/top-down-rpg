extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/flat_roof_example.tscn").instantiate(); root.add_child(scene)
	var house=scene.get_node("CasaComposta"); var body=house.authored_volumes()[0]
	house.rebuild(); assert(body.volume_error().is_empty())
	await physics_frame; await physics_frame
	var center: Vector3=body.to_global(Vector3(0,body.wall_height+2,0))
	var ray=PhysicsRayQueryParameters3D.create(center,center-Vector3.UP*3)
	var hit=root.get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.y-(body.wall_height+0.18))<0.01,"Flat slab has collision at its top")
	var above=PhysicsRayQueryParameters3D.create(Vector3(2.4,body.wall_height+0.4,-2),Vector3(3.6,body.wall_height+0.4,-2))
	assert(not root.get_world_3d().direct_space_state.intersect_ray(above).is_empty(),"Host wall above slab remains closed")
	var records=body.openings.duplicate(true); var before: float=body._generated.get_node("Roof").mesh.get_aabb().size.y
	body.parapet_enabled=false; body.rebuild()
	assert(body._generated.get_node("Roof").mesh.get_aabb().size.y<before-0.4)
	body.width-=0.2; house.rebuild(); assert(body.openings==records)
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta").authored_volumes()[0]
	assert(saved.canopy_roof==2 and not saved.parapet_enabled); copy.free()
	body.canopy_roof=0; body.rebuild(); assert(body.openings==records)
	body.structure_kind=1; body.canopy_roof=2; body.rebuild()
	assert(is_equal_approx(body.post_top(Vector3.ZERO),body.wall_height))
	print("FLAT_ROOF_COLLISION_HOST_WALL_PARAPET_SAVE_CONVERT_OK"); scene.free(); quit()
