extends RefCounted
static func create() -> Node3D:
	var group=preload("res://addons/house_builder/fortification.gd").new(); group.name="Fortificazione"
	var tower_script=preload("res://addons/house_builder/polygon_tower.gd")
	var west=tower_script.new(); west.name="TorreOvest"; west.width=8; west.depth=8; west.wall_height=5.6; west.roof_height=1
	var doors: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.2,"height":2.1}]; west.openings=doors
	group.add_child(west)
	var plan=preload("res://addons/house_builder/tower_interior_factory.gd").create(); west.add_child(plan)
	plan.get_node("PrimoPiano").add_child(preload("res://addons/house_builder/tower_interior_factory.gd").roof_stair())
	var east=tower_script.new(); east.name="TorreEst"; east.width=8; east.depth=8; east.wall_height=5.6; east.roof_height=1; east.position.x=16; group.add_child(east)
	var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); wall.name="Cortina"; wall.connect_to_tower=true; wall.target_tower=NodePath("../../TorreEst"); west.add_child(wall)
	return group
