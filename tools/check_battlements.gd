extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/square_tower_example.tscn").instantiate(); root.add_child(scene)
	var tower=scene.get_node("TorreQuadrata"); tower.rebuild(); assert(tower.volume_error().is_empty())
	await physics_frame; await physics_frame
	var y: float=tower.effective_elevation()+tower.roof_height*0.75
	var state=root.get_world_3d().direct_space_state
	var notch=PhysicsRayQueryParameters3D.create(Vector3(-1.92,y,1.9),Vector3(-1.92,y,2.8))
	assert(state.intersect_ray(notch).is_empty(),"Crenel notch is open")
	var merlon=PhysicsRayQueryParameters3D.create(Vector3(-1.44,y,1.9),Vector3(-1.44,y,2.8))
	assert(not state.intersect_ray(merlon).is_empty(),"Merlon has collision")
	tower.battlements_enabled=false; tower.rebuild(); await physics_frame; await physics_frame
	assert(not state.intersect_ray(notch).is_empty(),"Switch restores continuous parapet")
	tower.battlements_enabled=true; tower.battlement_spacing=1.3; tower.width=5.4; tower.rebuild()
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("TorreQuadrata")
	assert(saved.battlements_enabled and saved.battlement_spacing==1.3 and saved.width==5.4); copy.free()
	print("BATTLEMENTS_SOLID_NOTCH_TOGGLE_RESIZE_SAVE_OK"); scene.free(); quit()
