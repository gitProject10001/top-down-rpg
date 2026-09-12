extends SceneTree
const Village=preload("res://addons/village_builder/village.gd")
func _initialize() -> void: call_deferred("run")
func signature(records: Array) -> Array:
	return records.map(func(r): return [r.id,r.transform,r.request.data(),r.access])
func run() -> void:
	var scene=load("res://scenes/dev/village_organic_example.tscn").instantiate(); root.add_child(scene)
	var village=scene.get_node("Villaggio")
	assert(village.lots().size()>=18 and village.guides(4).size()==8)
	assert(village.surface_material.get_shader_parameter("road_mask")!=null)
	var records: Array=village.propose(); assert(not village.failed,village.report)
	assert(signature(records)==signature(village.propose()),"Organic layout is not deterministic")
	assert(records.size()==village.lots().size(),"Roundtrip changed the generated layout")
	for lot in village.lots():
		assert(not lot.protected_edit(),"Saved generated house falsely marked edited")
		assert(not lot.group_id.is_empty())
		for other in village.lots():
			if other==lot: continue
			assert(Geometry2D.intersect_polygons(lot.polygon(),other.polygon()).is_empty(),"Houses overlap")
			for shape in Village.access_shapes(lot.transform,lot.access_path):
				assert(Village.inside(shape,village.guides(0)[0].points),"Path outside boundary")
				assert(Geometry2D.intersect_polygons(shape,other.polygon()).is_empty(),"Path crosses another house")
		for group in village.guides(4): assert(Geometry2D.intersect_polygons(lot.polygon(),group.village_points()).is_empty(),"Court occupied by house")
		var endpoint: Vector3=lot.transform*lot.access_path[0]
		assert(village.road_shapes().any(func(poly): return Geometry2D.is_point_in_polygon(Vector2(endpoint.x,endpoint.z),poly)),"Path disconnected from road")
	var group=village.guides(4)[0]; group.locked=true
	var saved: Array=village.snapshot().filter(func(r): return r.group==group.stable_id)
	village.seed_value+=7
	var after: Array=village.propose(); assert(not village.failed,village.report)
	for record in saved: assert(after.any(func(r): return r.id==record.id and r.transform==record.transform and r.node==record.node),"Locked group changed")
	for record in saved:
		for other in after:
			if record.id==other.id: continue
			for path in Village.access_shapes(record.transform,record.access):
				assert(Geometry2D.intersect_polygons(path,Village.footprint(other.transform,other.request.footprint)).is_empty(),"New house blocks protected access")
	print("ORGANIC_SAVE_SEED_GROUP_LOCK_COURTS_PATHS_SURFACE_OK count=",records.size())
	scene.free(); quit()
