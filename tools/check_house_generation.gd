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
	house.free(); quit()
