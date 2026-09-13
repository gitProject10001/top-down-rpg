extends SceneTree
func _initialize() -> void: call_deferred("run")
func edge_ray(terrace: Node3D,frame: Transform3D) -> Dictionary:
	var a := terrace.to_global(frame*Vector3(0,0.48,-0.3))
	var b := terrace.to_global(frame*Vector3(0,0.48,0.3))
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b))
func run() -> void:
	var world=load("res://scenes/dev/side_stairs_example.tscn").instantiate(); root.add_child(world)
	var h=world.get_node("CasaConTerrazza"); var terrace=h.attached_components()[0]; var stair=terrace.stair_component()
	assert(stair!=null and stair.side==1 and not terrace.exterior_stairs)
	h.rebuild(); var right: Transform3D=terrace.stair_frame()
	await physics_frame; await physics_frame
	assert(edge_ray(terrace,right).is_empty())
	stair.side=2; h.rebuild(); var left: Transform3D=terrace.stair_frame()
	await physics_frame; await physics_frame
	assert(not edge_ray(terrace,right).is_empty() and edge_ray(terrace,left).is_empty())
	var id: String=stair.component_id
	var packed := PackedScene.new(); assert(packed.pack(world)==OK)
	var copy=packed.instantiate(); var restored=copy.get_node("CasaConTerrazza").attached_components()[0].stair_component()
	assert(restored.component_id==id and restored.side==2); copy.free()
	terrace.remove_child(stair); h.rebuild()
	await physics_frame; await physics_frame
	assert(not edge_ray(terrace,left).is_empty() and not terrace.has_stairs())
	stair.free(); world.free(); print("SIDE_STAIRS_EDGE_OPEN_CLOSE_SAVE_REMOVE_OK"); quit()
