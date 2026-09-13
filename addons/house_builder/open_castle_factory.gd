extends RefCounted
static func create() -> Node3D:
	var group=preload("res://addons/house_builder/fortification_factory.gd").create_inhabitable_enclosure()
	group.name="CastelloAperto"; group.entry_position.x=13; group.courtyard_ground_color=Color(0.25,0.29,0.16)
	for tower in group.towers(): tower.position*=26.0/16.0
	var keep=preload("res://addons/house_builder/keep_factory.gd").create(); keep.position=Vector3(8,0,-18); group.add_child(keep)
	var volumes := Node3D.new(); volumes.name="Volumes"; keep.add_child(volumes)
	volumes.add_child(preload("res://addons/house_builder/keep_factory.gd").create_accessory())
	var hall=preload("res://addons/house_builder/house.gd").new(); hall.name="CorpoServizi"
	hall.width=5; hall.depth=5; hall.wall_height=2.8; hall.roof_height=1.8; hall.position=Vector3(18.5,0,-18.5); hall.archetype_id="hall"
	var doors: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.3,"height":2.1}]; hall.openings=doors; group.add_child(hall)
	var plan=preload("res://addons/house_builder/plan.gd").new(); plan.name="InteriorPlan"; plan.floor_height=2.8; hall.add_child(plan)
	var level := Node3D.new(); level.name="PianoTerra"; plan.add_child(level)
	return group
