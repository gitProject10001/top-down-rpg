extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func run() -> void:
	var scene=load("res://scenes/dev/castle_raised_courtyard_example.tscn").instantiate(); root.add_child(scene)
	await settle(); var group=scene.get_node("Castello"); var court=group.get_node("CorteRialzata")
	assert(group.diagnostics().is_empty())
	var space=root.get_world_3d().direct_space_state
	for item in [[Vector3(8,0,-2),0.6],[Vector3(12,0,-8),1.2]]:
		var p: Vector3=item[0]
		var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP))
		assert(not hit.is_empty() and absf(hit.position.y-item[1])<0.02,"Platform and ramp support player")
	var back=group.get_node("TorreNordOvest"); var wall=back.get_node("Cortina")
	assert(wall.connection_error().is_empty() and is_equal_approx(wall._base_drop,1.2))
	assert(not group.resize_proposal(group.layout_size()).has("error"),"Different base heights preserve rectangle resize")
	court.elevation=1.5; await settle()
	assert(group.diagnostics().any(func(issue): return "quota attesa" in issue.message),"Manual height mismatch is visible")
	court.elevation=1.2; await settle(); assert(group.diagnostics().is_empty())
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); assert(is_equal_approx(copy.get_node("Castello/TorreNordOvest").position.y,1.2)); copy.free()
	assert(preload("res://addons/house_builder/raised_courtyard_factory.gd").proposal(group).has("error"),"Duplicate does not overwrite authored layout")
	scene.free(); print("RAISED_COURT_COLLISION_BASES_DIAGNOSTICS_SAVE_OK"); quit()
