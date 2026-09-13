extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/wall_frame_example.tscn").instantiate(); root.add_child(scene)
	var porch=scene.get_node("CasaComposta/Volumes/Portico"); var link=porch.get_node("FrameLinks").get_child(1)
	assert(link.validation_error().is_empty() and link.segments().size()==2)
	var house=porch.volume_host()
	for wall in 4:
		porch.host_wall=wall; house.rebuild(); assert(link.validation_error().is_empty())
		var endpoint: Vector3=porch.transform*link.wall_endpoint()
		assert(absf(house.wall_normal(wall).dot(endpoint-house.wall_point(wall,0,0)))<0.001,"Endpoint lies on actual facade")
	porch.host_wall=0; house.rebuild()
	var post=link.support(link.support_a); var before: Vector3=link.wall_endpoint()
	post.position.x+=0.2; porch.rebuild(); assert(is_equal_approx(link.wall_endpoint().x,before.x+0.2))
	link.wall_offset=0.2; porch.rebuild(); assert(is_equal_approx(link.wall_endpoint().x,post.position.x+0.2))
	porch.attached=false; porch.rebuild(); assert(not link.validation_error().is_empty() and link.segments().is_empty())
	porch.attached=true; porch.rebuild(); assert(link.validation_error().is_empty())
	link.wall_offset=10; porch.rebuild(); assert(not link.validation_error().is_empty())
	link.wall_offset=0.2
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta/Volumes/Portico/FrameLinks").get_child(1)
	assert(saved.endpoint_mode==1 and saved.wall_offset==0.2 and saved.support_a==post.support_id); copy.free()
	print("WALL_FRAME_FACADES_FOLLOW_DETACH_INVALID_SAVE_OK"); scene.free(); quit()
