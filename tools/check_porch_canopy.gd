extends SceneTree
func _initialize() -> void: call_deferred("run")
func ray(a: Vector3,b: Vector3) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b))
func run() -> void:
	var scene=load("res://scenes/dev/porch_canopy_example.tscn").instantiate(); root.add_child(scene)
	var house=scene.get_node("CasaComposta"); var porch=house.authored_volumes()[0]; var canopy=house.authored_volumes()[1]
	house.rebuild(); assert(porch.volume_error().is_empty())
	await physics_frame; await physics_frame
	assert(not ray(Vector3(0,1,3.5),Vector3(0,1,4.5)).is_empty(),"Porch never cuts the host wall")
	assert(ray(porch.to_global(Vector3(-3,1,0.4)),porch.to_global(Vector3(3,1,0.4))).is_empty(),"Open sides remain traversable")
	var post := Vector3((canopy.width-canopy.post_size)*0.5,1,(canopy.depth-canopy.post_size)*0.5)
	assert(not ray(canopy.to_global(post-Vector3(0.5,0,0)),canopy.to_global(post+Vector3(0.5,0,0))).is_empty(),"Posts have collision")
	var records: Array[Dictionary]=[{"kind":"window","wall":0,"u":0.0}]; porch.openings=records
	house.rebuild(); assert(porch.all_openings().is_empty() and porch.openings.size()==1,"Conversion preserves but suppresses manual openings")
	porch.attached=false; porch.position=Vector3(-6,0,0); porch.width=5; porch.post_spacing=1.8; house.rebuild()
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta").authored_volumes()[0]
	assert(saved.structure_kind==1 and not saved.attached and saved.width==5 and saved.post_spacing==1.8 and saved.openings==records); copy.free()
	print("PORCH_WALL_OPEN_SIDES_POST_COLLISION_SAVE_OK"); scene.free(); quit()
