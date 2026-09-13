extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/porch_canopy_example.tscn").instantiate(); root.add_child(scene)
	var porch=scene.get_node("CasaComposta/Volumes/Portico"); var link=porch.get_node("FrameLinks").get_child(0)
	assert(link.validation_error().is_empty() and link.segments().size()==3)
	var post=link.support(link.support_a); var before: Vector3=link.endpoints()[0]
	post.position.x+=0.3; post.name="PaloRinominato"; porch.rebuild()
	assert(is_equal_approx(link.endpoints()[0].x,before.x+0.3),"Connection follows position and survives rename")
	porch.roof_height+=0.5; porch.rebuild(); assert(link.endpoints()[0].y>before.y)
	await physics_frame; await physics_frame
	var middle: Vector3=porch.to_global(link.endpoints()[0].lerp(link.endpoints()[1],0.5))
	var ray=PhysicsRayQueryParameters3D.create(middle-Vector3(0,0,0.4),middle+Vector3(0,0,0.4))
	assert(not root.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Authored beam has collision")
	link.braces=false; porch.rebuild(); assert(link.segments().size()==1)
	var id: String=link.link_id
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta/Volumes/Portico/FrameLinks").get_child(0)
	assert(saved.link_id==id and not saved.braces and saved.support_a==post.support_id); copy.free()
	var parent=post.get_parent(); parent.remove_child(post); porch.rebuild()
	assert(not link.validation_error().is_empty() and link.segments().is_empty(),"Missing support suspends the connection")
	parent.add_child(post); porch.rebuild(); assert(link.validation_error().is_empty())
	# Exercise horizontal depth-axis beams: cross product must not collapse.
	porch.canopy_roof=0; porch.rebuild()
	var vertices: PackedVector3Array=porch._generated.get_node("Walls").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in vertices: assert(v.is_finite())
	print("FRAME_LINK_FOLLOW_RENAME_COLLISION_SAVE_MISSING_SUPPORT_OK"); scene.free(); quit()
