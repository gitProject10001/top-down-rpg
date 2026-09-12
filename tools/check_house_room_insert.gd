extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Plan=preload("res://addons/house_builder/plan.gd")
const Generator=preload("res://addons/house_builder/plan_generator.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var house := House.new(); house.width=10; house.depth=10; root.add_child(house)
	var plan := Plan.new(); plan.name="InteriorPlan"; house.add_child(plan)
	var level := Node3D.new(); plan.add_child(level)
	plan.requested_rooms=3; plan.rebuild()
	plan.apply_records(0,plan.propose_rooms(0))
	var original := plan.level_records(0)
	var source: Dictionary=original.filter(func(r): return r.kind==0 and r.id!="hall")[0]
	var bounds := Generator.rect(source); bounds.size.y*=0.5
	var new_room := Generator.room("manual_test",bounds,plan.floor_height,"camera")
	new_room.generated=false
	plan.apply_records(0,original+[new_room])
	var before := plan.level_records(0)
	var after := plan.propose_insert_room(0,"manual_test")
	assert(after!=before,plan.generation_report)
	assert(after.any(func(r): return r.kind==1 and "manual_test" in r.room_ids and r.has_door),"New room has no door/wall")
	assert(Generator.walkability(after.filter(func(r): return r.kind==0),after).is_empty())
	plan.apply_records(0,after)
	var manual: Node3D
	for e in level.get_children():
		if e.stable_id=="manual_test": manual=e
	assert(str(manual.name).begins_with("Camera"))
	manual.room_type="cucina"; manual.refresh_room_name()
	assert(str(manual.name).begins_with("Cucina"))
	manual.display_name="Camera degli ospiti"; manual.refresh_room_name()
	assert(str(manual.name)=="Camera degli ospiti")
	manual.name="Nome personale"; manual.room_type="soggiorno"; manual.refresh_room_name()
	assert(str(manual.name)=="Nome personale","Custom scene name lost")
	plan.apply_records(0,before)
	for e in level.get_children():
		if e.stable_id==source.id: e.locked=true
	assert(plan.propose_insert_room(0,"manual_test")==plan.level_records(0),"Locked room was carved")
	print("HOUSE_ROOM_INSERT_WALL_DOOR_NAMES_LOCK_OK")
	house.free(); quit()
