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


static func create_enclosure() -> Node3D:
	var group=create(); group.name="Castello"; group.courtyard_entry=true
	var west=group.get_node("TorreOvest")
	var records: Array[Dictionary]=[{"kind":"door","wall":3,"width":1.2,"height":2.1}]
	west.openings=records
	var tower_script=preload("res://addons/house_builder/polygon_tower.gd")
	for item in [["TorreNordEst",Vector3(16,0,-16)],["TorreNordOvest",Vector3(0,0,-16)]]:
		var tower=tower_script.new(); tower.name=item[0]; tower.position=item[1]
		tower.width=8; tower.depth=8; tower.wall_height=5.6; tower.roof_height=1; group.add_child(tower)
	for link in [["TorreEst","TorreNordEst",4,0],["TorreNordEst","TorreNordOvest",6,2],["TorreNordOvest","TorreOvest",0,4]]:
		var wall=preload("res://addons/house_builder/curtain_wall.gd").new(); wall.name="Cortina"
		wall.connect_to_tower=true; wall.tower_face=link[2]; wall.target_face=link[3]
		wall.target_tower=NodePath("../../"+link[1]); wall.gate_enabled=false; group.get_node(link[0]).add_child(wall)
	return group


static func tower_plan(tower: Node3D) -> Node3D:
	var plan=preload("res://addons/house_builder/tower_interior_factory.gd").create()
	plan.floor_height=tower.wall_height*0.5
	plan.get_node("PianoTerra/ScalaPrimoPiano").dimensions.y=plan.floor_height
	plan.get_node("PrimoPiano").add_child(preload("res://addons/house_builder/tower_interior_factory.gd").roof_stair())
	return plan

static func courtyard_openings(group: Node3D,tower: Node3D) -> Array[Dictionary]:
	var records: Array[Dictionary]=tower.openings.duplicate(true)
	for record in records:
		if record.get("kind","")=="door": return records
	var center := Vector3.ZERO
	for other in group.towers(): center+=other.position
	center/=group.towers().size()
	var direction: Vector3=tower.basis.inverse()*(center-tower.position)
	var best := -INF; var face := 1
	for candidate in [1,3,5,7]:
		var score: float=tower.wall_normal(candidate).dot(direction.normalized())
		if score>best: best=score; face=candidate
	var door := {"kind":"door","wall":face,"width":1.2,"height":2.1}
	if tower.opening_fits(door): records.append(door)
	return records

static func create_inhabitable_enclosure() -> Node3D:
	var group=create_enclosure()
	for tower in group.towers():
		if tower.has_node("InteriorPlan"): continue
		tower.openings=courtyard_openings(group,tower)
		tower.add_child(tower_plan(tower))
	return group
