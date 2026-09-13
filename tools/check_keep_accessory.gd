extends SceneTree
func _initialize() -> void: call_deferred("run")
func settle() -> void:
	for i in 30: await physics_frame
func passage(keep: Node3D) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(keep.to_global(Vector3(-2.5,1,0)),keep.to_global(Vector3(-3.5,1,0))))
func run() -> void:
	var scene=load("res://scenes/dev/castle_keep_accessory_example.tscn").instantiate(); root.add_child(scene)
	var keep=scene.get_node("Castello/Mastio"); var volume=keep.get_node("Volumes/CorpoAccessorio")
	await settle(); assert(volume.volume_error().is_empty())
	var records: Array=keep.openings.duplicate(true)
	assert(not passage(keep).is_empty(),"Closed door has collision")
	volume.junction_mode=0; await settle()
	assert(passage(keep).is_empty(),"Open junction cuts both wall collisions")
	volume.attached=false; await settle()
	assert(not passage(keep).is_empty(),"Detaching restores host wall")
	volume.attached=true; await settle(); assert(passage(keep).is_empty())
	volume.depth=20; await settle()
	assert(not volume.volume_error().is_empty(),"Oversized annex conflicts with enclosure")
	assert(not passage(keep).is_empty(),"Invalid attachment does not leave a hole")
	volume.depth=2.8; await settle(); assert(passage(keep).is_empty())
	assert(keep.openings==records,"Authored windows never modified")
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); assert(copy.get_node("Castello/Mastio/Volumes/CorpoAccessorio").junction_mode==0); copy.free()
	volume.get_parent().remove_child(volume); volume.free(); await settle()
	assert(not passage(keep).is_empty(),"Deleting annex restores wall")
	scene.free(); print("KEEP_ACCESSORY_CUT_DETACH_INVALID_DELETE_SAVE_OK"); quit()
