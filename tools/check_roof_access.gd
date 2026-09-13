extends SceneTree
func _initialize() -> void: call_deferred("run")
func gap_ray(body: Node3D) -> Dictionary:
	var frame: Transform3D=body.stair_frame()
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(body.to_global(frame*Vector3(0,0.35,-0.5)),body.to_global(frame*Vector3(0,0.35,0.35))))
func run() -> void:
	var scene=load("res://scenes/dev/roof_access_example.tscn").instantiate(); root.add_child(scene)
	var body=scene.get_node("CasaComposta").authored_volumes()[0]; var stairs=body.stair_component()
	for side in 3:
		stairs.side=side; body.rebuild(); await physics_frame; await physics_frame
		assert(body.has_roof_access() and gap_ray(body).is_empty(),"Gap follows stair side")
		stairs.enabled=false; body.rebuild(); await physics_frame; await physics_frame
		assert(not gap_ray(body).is_empty(),"Disabled access restores parapet collision")
		stairs.enabled=true
	body.wall_height+=0.4; body.rebuild(); assert(is_equal_approx(stairs.position.y,body.effective_elevation()))
	stairs.width=10; body.rebuild(); assert(not body.roof_access_error().is_empty() and not stairs.visible)
	stairs.width=1.2; body.rebuild()
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta").authored_volumes()[0].stair_component()
	assert(saved.component_id==stairs.component_id and saved.side==2); copy.free()
	print("ROOF_ACCESS_GAPS_SIDES_DISABLE_RESIZE_INVALID_SAVE_OK"); scene.free(); quit()
