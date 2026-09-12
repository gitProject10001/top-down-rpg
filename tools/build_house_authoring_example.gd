extends SceneTree
const House=preload("res://addons/house_builder/house.gd")
const Plan=preload("res://addons/house_builder/plan.gd")
func _initialize() -> void: call_deferred("run")
func own(node: Node,house: Node) -> void:
	if node!=house: node.owner=house
	for child in node.get_children(): own(child,house)
func run() -> void:
	var house := House.new(); house.name="CasaModificabile"; house.width=7; house.depth=10
	house.openings=[{"kind":"door","wall":0,"u":0.0,"width":1.4,"height":2.3},{"kind":"window","wall":1,"u":-0.45,"y":1.5},{"kind":"window","wall":2,"u":-0.6,"y":1.5}]
	root.add_child(house)
	var plan := Plan.new(); plan.name="InteriorPlan"; plan.seed_value=22; house.add_child(plan)
	for i in 2:
		var level := Node3D.new(); level.name="Piano_%d"%(i+1); plan.add_child(level)
	plan.rebuild()
	for i in 2:
		var proposal := plan.propose_rooms(i); assert(not proposal.is_empty(),plan.generation_report)
		plan.apply_records(i,proposal)
		plan.apply_records(i,plan.propose_furniture(i))
		print("EXAMPLE_FLOOR ",i," ",plan.generation_report)
	own(house,house)
	var packed := PackedScene.new(); assert(packed.pack(house)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/dev/house_authoring_example.tscn")==OK)
	house.free(); quit()
