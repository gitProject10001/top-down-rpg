extends RefCounted
## Initial authored layout; subsequent rebuilding never replaces these nodes.
static func create() -> Node3D:
	var plan=preload("res://addons/house_builder/plan.gd").new()
	plan.name="InteriorPlan"; plan.floor_height=2.8
	var ground := Node3D.new(); ground.name="PianoTerra"; ground.set_meta("floor_id","tower_ground"); plan.add_child(ground)
	var upper := Node3D.new(); upper.name="PrimoPiano"; upper.set_meta("floor_id","tower_upper"); plan.add_child(upper)
	var stairs=preload("res://addons/house_builder/plan_element.gd").new()
	stairs.name="ScalaPrimoPiano"; stairs.kind=2; stairs.stable_id="tower_stair_0"
	stairs.dimensions=Vector3(1.2,2.8,4.2); ground.add_child(stairs)
	return plan
