extends RefCounted
static func create() -> Node3D:
	var keep=preload("res://addons/house_builder/keep.gd").new()
	keep.name="Mastio"; keep.width=6; keep.depth=6; keep.wall_height=8.4; keep.roof_height=2.2
	var openings: Array[Dictionary]=[{"kind":"door","wall":0,"width":1.4,"height":2.2}]
	for y in [3.6,6.4]:
		for wall in [0,1,2,3]:
			openings.append({"kind":"window","wall":wall,"width":0.7,"height":1.2,"y":y})
	keep.openings=openings
	var plan=preload("res://addons/house_builder/plan.gd").new(); plan.name="InteriorPlan"; plan.floor_height=2.8; keep.add_child(plan)
	for i in 3:
		var level := Node3D.new(); level.name=["PianoTerra","PrimoPiano","SecondoPiano"][i]
		level.set_meta("floor_id","keep_floor_%d"%i); plan.add_child(level)
		if i==2: continue
		var stair=preload("res://addons/house_builder/plan_element.gd").new()
		stair.name="ScalaPiano%d"%(i+1); stair.kind=2; stair.stable_id="keep_stair_%d"%i
		stair.dimensions=Vector3(1.2,2.8,3.8); stair.position.x=1.2 if i==0 else -1.2
		stair.rotation.y=0 if i==0 else PI; level.add_child(stair)
	return keep

static func placement(group: Node3D) -> Dictionary:
	if group.buildings().size()!=group.towers().size(): return {"error":"Il gruppo contiene già un edificio indipendente: modifica quello esistente."}
	var check: Dictionary=group.resize_proposal(group.layout_size())
	if check.has("error"): return check
	var low: Vector3=group.towers()[0].position; var high := low
	var clearance := Vector2.ZERO
	for tower in group.towers():
		low=low.min(tower.position); high=high.max(tower.position)
		clearance=clearance.max(Vector2(tower.width,tower.depth))
	if high.x-low.x-clearance.x<8 or high.z-low.z-clearance.y<8:
		return {"error":"Allarga il recinto: servono 8 m liberi centrali per il mastio e i passaggi."}
	return {"position":Vector3((low.x+high.x)*0.5,0,(low.z+high.z)*0.5)}

static func create_accessory() -> Node3D:
	var volume=preload("res://addons/house_builder/volume.gd").new()
	volume.name="CorpoAccessorio"; volume.width=3; volume.depth=2.8; volume.wall_height=2.6
	volume.canopy_roof=2; volume.parapet_enabled=false; volume.host_wall=3
	volume.junction_mode=1; volume.junction_width=1.4
	var records: Array[Dictionary]=[{"kind":"window","wall":0,"u":0.0,"y":1.4}]; volume.openings=records
	return volume
