extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/roof_door_example.tscn").instantiate(); root.add_child(scene)
	var host=scene.get_node("CasaComposta"); var volume=host.authored_volumes()[0]; var plan=host.get_node("InteriorPlan")
	host.rebuild(); assert(volume.roof_door_error().is_empty())
	var manual=host.openings.duplicate(true); var count: int=host.all_openings().size()
	volume.roof_door_enabled=false; host.rebuild(); assert(host.all_openings().size()==count-1 and host.openings==manual)
	volume.roof_door_enabled=true; volume.wall_height+=0.25; host.rebuild()
	assert(not volume.roof_door_error().is_empty() and host.all_openings().size()==count-1,"Mismatched floor suspends door")
	volume.wall_height-=0.25; host.rebuild(); assert(volume.roof_door_error().is_empty())
	var level=host.authored_floor(volume.roof_door_floor_id); level.name="PianoRinominato"; assert(volume.roof_door_error().is_empty())
	volume.roof_door_open=true
	var packed := PackedScene.new(); assert(packed.pack(scene)==OK)
	var copy=packed.instantiate(); var saved=copy.get_node("CasaComposta").authored_volumes()[0]
	assert(saved.roof_door_floor_id==volume.roof_door_floor_id and saved.roof_door_open); copy.free()
	volume.attached=false; host.rebuild(); assert(not volume.roof_door_error().is_empty())
	assert(plan.levels().size()==2 and host.openings==manual,"No manual floors or openings are rewritten")
	print("ROOF_DOOR_FLOOR_ID_MISMATCH_REMOVE_SAVE_OK"); scene.free(); quit()
