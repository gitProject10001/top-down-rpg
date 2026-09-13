extends SceneTree
func _initialize() -> void: call_deferred("run")
func hit(post: Node3D) -> Dictionary:
	var center: Vector3=post.volume().to_global(post.position+Vector3.UP)
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center-Vector3(0.5,0,0),center+Vector3(0.5,0,0)))
func run() -> void:
	var scene=load("res://scenes/dev/porch_canopy_example.tscn").instantiate(); root.add_child(scene)
	var porch=scene.get_node("CasaComposta/Volumes/Portico"); var supports=porch.get_node("Supports"); var post=supports.get_child(0)
	var id: String=post.support_id; var count: int=supports.get_child_count()
	post.position.x+=0.25; post.section=0.37; var pose: Vector3=post.position
	porch.depth+=1; porch.post_spacing=1.5; porch.rebuild()
	await physics_frame; await physics_frame
	assert(post.position==pose and post.section==0.37 and supports.get_child_count()==count)
	assert(not hit(post).is_empty(),"Authored support collision follows the edit")
	post.enabled=false; porch.rebuild(); await physics_frame; await physics_frame
	assert(hit(post).is_empty(),"Disabling removes collision")
	post.enabled=true; post.position.x=20; porch.rebuild()
	assert(not post.valid() and not post._get_configuration_warnings().is_empty())
	post.position=pose; porch.rebuild()
	var removed=supports.get_child(count-1); supports.remove_child(removed); removed.free(); porch.rebuild()
	assert(supports.get_child_count()==count-1,"Deleted supports never respawn")
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta/Volumes/Portico/Supports").get_child(0)
	assert(saved.support_id==id and saved.position==pose and saved.section==0.37); copy.free()
	print("AUTHORED_SUPPORTS_EDIT_RESIZE_COLLISION_DELETE_SAVE_OK"); scene.free(); quit()
