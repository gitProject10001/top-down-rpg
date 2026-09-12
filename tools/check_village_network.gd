extends SceneTree
const Network=preload("res://addons/village_builder/path_network.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/dev/village_organic_example.tscn").instantiate(); root.add_child(scene)
	var village=scene.get_node("Villaggio"); var records: Array=village.snapshot()
	assert(Network.validate(village,records).is_empty())
	var shared := Network.shared(village,records)
	assert(shared.size()==village.guides(4).size(),"Every populated court must have a trunk")
	assert(Network.unify(village,records).is_empty())
	for trunk in shared:
		for record in records:
			if record.group!=trunk.group: continue
			var path := Network.world_path(record)
			for i in trunk.points.size(): assert(path[i].distance_to(trunk.points[i])<0.01,"Court paths do not share their trunk")
	var road=village.guides(1)[1]; var points: PackedVector2Array=road.points.duplicate()
	road.position.x=150
	assert("Non raggiungibili" in Network.validate(village,records),"Disconnected main road accepted")
	road.position.x=0
	var guide=village.guides(5)[0]; var saved: PackedVector2Array=guide.points.duplicate()
	guide.points=PackedVector2Array([Vector2(100,100),saved[-1]])
	assert("primo punto" in Network.unify(village,village.snapshot()),"Detached manual trunk accepted")
	var house: Vector3=village.lots()[0].position
	guide.points=PackedVector2Array([saved[0],Vector2(house.x,house.z),saved[-1]])
	assert("invade" in Network.unify(village,village.snapshot()),"Manual trunk through a house accepted")
	guide.points=saved
	road.point_widths=PackedFloat32Array([2,4,6,4,3,2])
	var inserted := points.duplicate(); inserted.insert(1,(points[0]+points[1])*0.5)
	var widths: PackedFloat32Array=road.widths_for_points(inserted)
	assert(is_equal_approx(widths[1],3.0),"Inserted vertex must interpolate width")
	assert(Network.ribbon(PackedVector2Array([Vector2.ZERO,Vector2(8,0),Vector2(8,8)]),PackedFloat32Array([2,4,2])).size()==5,"Missing rounded joins")
	print("NETWORK_SHARED_TRUNKS_DISCONNECTION_MANUAL_COLLISION_WIDTHS_OK")
	scene.free(); quit()
