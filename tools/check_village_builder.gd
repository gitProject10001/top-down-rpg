extends SceneTree
const Village=preload("res://addons/village_builder/village.gd")
const Guide=preload("res://addons/village_builder/guide.gd")
func _initialize() -> void: call_deferred("run")
func guide(village: Node,kind: int,id: String,points: PackedVector2Array) -> Node3D:
	var node := Guide.new(); node.kind=kind; node.stable_id=id; node.points=points; node.name=id; village.add_child(node); return node
func signature(records: Array) -> Array: return records.map(func(r): return [r.id,r.transform,r.request.data()])
func run() -> void:
	var village := Village.new(); village.name="Villaggio"; root.add_child(village)
	guide(village,0,"Perimetro",PackedVector2Array([Vector2(-30,-24),Vector2(30,-24),Vector2(30,24),Vector2(-30,24)]))
	var road := guide(village,1,"ViaPrincipale",PackedVector2Array([Vector2(-25,0),Vector2(25,0)]))
	guide(village,2,"Quartiere",PackedVector2Array([Vector2(-29,-23),Vector2(29,-23),Vector2(29,23),Vector2(-29,23)]))
	var proposal := village.propose(); assert(not village.failed,village.report); assert(proposal.size()>=6)
	assert(signature(proposal)==signature(village.propose()),"Seed not deterministic")
	village.apply(proposal)
	for lot in village.lots():
		assert(not lot.protected_edit(),"Fresh lot marked edited")
		assert(lot.get_node("Edificio").width==lot.request.footprint.x)
		var house=lot.get_node("Edificio")
		var normal: Vector3=lot.basis*house.wall_normal(lot.request.entrance_side)
		assert(normal.dot(Vector3(1,0,1).normalized())>0.65,"Entrance faces away from fixed camera")
		assert(lot.access_path.size()>=2)
		var start: Vector3=lot.transform*lot.access_path[0]
		assert(absf(start.z)<0.01,"Access must connect to the main road")
		assert(Village.inside(lot.polygon(),village.guides(0)[0].points))
		for other in village.lots():
			if other!=lot: assert(Geometry2D.intersect_polygons(lot.polygon(),other.polygon()).is_empty())
			if other!=lot:
				for path in Village.access_shapes(lot.transform,lot.access_path): assert(Geometry2D.intersect_polygons(path,other.polygon()).is_empty(),"Access blocked by another house")
	print("VILLAGE_SEED_CONTAINMENT_NO_OVERLAP_OK count=",proposal.size())
	print("VILLAGE_FIXED_CAMERA_ENTRANCES_ACCESS_CLEARANCE_OK")
	var before := village.snapshot(); var first=village.lots()[0]
	first.get_node("Edificio").weathered=false
	assert(first.protected_edit())
	village.seed_value+=1; var regenerated := village.propose(); assert(not village.failed,village.report)
	village.apply(regenerated)
	assert(first.get_parent()==village and not first.get_node("Edificio").weathered,"Edited house lost")
	village.apply(before); assert(village.lots()[0]==first)
	var saved_points: PackedVector2Array=road.points
	road.points=PackedVector2Array([Vector2(-25,first.position.z),Vector2(25,first.position.z)])
	village.propose(); assert(village.failed and "protetto" in village.report,"Road conflict silently accepted")
	road.points=saved_points
	var deleted_id: String=first.stable_id; village.remove_child(first)
	var after_delete := village.propose(); assert(not after_delete.any(func(r): return r.id==deleted_id))
	village.add_child(first); village.apply(before)
	village.owner=null
	for child in village.get_children(): set_owner_tree(child,village)
	var packed := PackedScene.new(); assert(packed.pack(village)==OK)
	assert(ResourceSaver.save(packed,"user://village_roundtrip.tscn")==OK)
	var copy=load("user://village_roundtrip.tscn").instantiate(); root.add_child(copy)
	assert(copy.lots().size()==village.lots().size())
	for lot in copy.lots():
		if lot.stable_id==deleted_id: assert(lot.protected_edit())
		else: assert(not lot.protected_edit(),"Serialization falsely protects unchanged lots")
	print("VILLAGE_PROTECTED_CONFLICT_DELETE_UNDO_SAVE_OK")
	village.free(); copy.free(); first=null; quit()
func set_owner_tree(node: Node,scene: Node) -> void:
	node.owner=scene
	for child in node.get_children(): set_owner_tree(child,scene)
