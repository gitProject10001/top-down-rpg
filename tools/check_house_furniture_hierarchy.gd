extends SceneTree
const Element=preload("res://addons/house_builder/plan_element.gd")
func _initialize() -> void: call_deferred("run")
func own(node: Node,scene: Node) -> void:
	if node!=scene: node.owner=scene
	for child in node.get_children(): own(child,scene)
func run() -> void:
	var house=load("res://scenes/dev/house_authoring_example.tscn").instantiate()
	root.add_child(house)
	var plan=house.get_node("InteriorPlan")
	var before: Dictionary={}
	for r in plan.level_records(0):
		if r.kind==3: before[r.id]=r.position
	plan.organize_furniture()
	var furniture: Node3D
	for e in plan.level_elements(plan.levels()[0]):
		if e.kind!=3: continue
		assert(e.get_parent() is Element and e.get_parent().kind==0)
		assert(e.record().position.is_equal_approx(before[e.stable_id]),"Migration moved furniture")
		assert(not e.protected_edit(),"Migration falsely marked furniture edited")
		assert(e.plan()==plan)
		furniture=e
	assert(furniture!=null)
	var room: Node3D=furniture.get_parent()
	var world_before: Vector3=furniture.global_position
	room.position.x+=0.25
	assert(furniture.global_position.is_equal_approx(world_before+Vector3(0.25,0,0)))
	assert(furniture.protected_edit(),"Moving a room must protect its moved furniture")
	room.position.x-=0.25
	var records: Array=plan.level_records(0)
	var without: Array=records.filter(func(r): return r.id!=furniture.stable_id)
	plan.apply_records(0,without)
	assert(furniture.get_parent()==null)
	plan.apply_records(0,records)
	assert(furniture.get_parent()==room,"Undo must restore the same node under the room")
	assert(furniture.record().position.is_equal_approx(before[furniture.stable_id]))
	own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK)
	assert(ResourceSaver.save(packed,"user://house_hierarchy_roundtrip.tscn")==OK)
	var restored=load("user://house_hierarchy_roundtrip.tscn").instantiate(); root.add_child(restored)
	var restored_plan=restored.get_node("InteriorPlan")
	for e in restored_plan.level_elements(restored_plan.levels()[0]):
		if e.kind==3:
			assert(e.get_parent().kind==0 and e.owner==restored)
			assert(e.record().position.is_equal_approx(before[e.stable_id]))
	print("HOUSE_FURNITURE_HIERARCHY_MIGRATION_MOVE_UNDO_SAVE_OK")
	house.free(); restored.free(); quit()
