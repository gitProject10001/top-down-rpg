extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Plan=preload("res://addons/house_builder/plan.gd")
const Generator=preload("res://addons/house_builder/plan_generator.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var house := House.new(); house.width=7; house.depth=10; root.add_child(house)
	house.openings=[{"kind":"door","wall":0,"u":0.0,"width":1.4,"height":2.3}]
	var plan := Plan.new(); plan.name="InteriorPlan"; house.add_child(plan)
	for i in 2:
		var level := Node3D.new(); level.name="Piano_%d"%i; plan.add_child(level)
	plan.rebuild()
	for seed_value in [11,22,33]:
		plan.seed_value=seed_value
		for floor_index in 2:
			var records := plan.propose_rooms(floor_index)
			assert(not records.is_empty(),plan.generation_report)
			assert(records==plan.propose_rooms(floor_index),"Generation must be deterministic")
			var rooms: Array=records.filter(func(r): return r.kind==0)
			var walls: Array=records.filter(func(r): return r.kind==1)
			assert(Generator.validate(rooms,walls).is_empty())
			plan.apply_records(floor_index,records)
			print("HOUSE_PLAN_GENERATED seed=",seed_value," floor=",floor_index," rooms=",rooms.size())
	house.wing_enabled=true
	var wing_records := plan.propose_rooms(0)
	assert(wing_records.any(func(r): return r.id=="wing"),plan.generation_report)
	print("HOUSE_PLAN_WING_CONNECTED_OK")
	plan.apply_records(0,wing_records)
	var level := plan.levels()[0]
	var hall: Node3D
	var wall: Node3D
	for e in level.get_children():
		if e.stable_id=="hall": hall=e
		if e.kind==1: wall=e
	hall.locked=true
	var original: Dictionary=hall.record()
	plan.seed_value=88
	plan.apply_records(0,plan.propose_rooms(0))
	assert(hall.record()==original and hall.locked,"Locked room changed")
	wall.door_width=1.35
	var edited: Dictionary=wall.record()
	plan.apply_records(0,plan.propose_walls(0))
	assert(wall.record()==edited,"Manual wall edit changed")
	var before := plan.level_records(0)
	var id: String=wall.stable_id
	level.remove_child(wall); plan.observe_deletions()
	var after := plan.propose_walls(0)
	assert(not after.any(func(r): return r.id==id),"Deleted wall returned")
	level.add_child(wall); plan.observe_deletions()
	assert(not plan.deleted_ids.has("0/"+id),"Undo deletion not observed")
	plan.apply_records(0,after); plan.apply_records(0,before)
	assert(wall.get_parent()==level,"Undo replaced authored node identity")
	var blocked := before.duplicate(true)
	blocked.append({"id":"blocker","kind":3,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"dimensions":Vector3(20,2,20)})
	assert(plan.checked_proposal(0,blocked)==plan.level_records(0),"Invalid proposal applied")
	print("HOUSE_PLAN_LOCK_EDIT_DELETE_RESTORE_CLEARANCE_OK")
	var furniture := plan.propose_furniture(0)
	assert(furniture==plan.propose_furniture(0),"Furniture is not deterministic")
	var props: Array=furniture.filter(func(r): return r.kind==3)
	assert(props.size()>0,"No furniture fitted")
	assert(Generator.walkability(furniture.filter(func(r): return r.kind==0),furniture).is_empty())
	plan.apply_records(0,furniture)
	var prop: Node3D
	for e in level.get_children():
		if e.kind==3: prop=e; break
	prop.position.x+=0.03
	var pose: Vector3=prop.position
	plan.apply_records(0,plan.propose_furniture(0))
	assert(prop.position==pose,"Moved furniture lost")
	plan.apply_records(0,plan.propose_furniture(0,"",true))
	assert(prop.get_parent()==level,"Cleanup removed edited furniture")
	print("HOUSE_PLAN_FURNITURE_SEED_CLEARANCE_PROTECTION_OK count=",props.size())
	house.free(); quit()
