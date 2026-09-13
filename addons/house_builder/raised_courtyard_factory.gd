extends RefCounted
static func proposal(group: Node3D) -> Dictionary:
	if group.has_node("CorteRialzata"): return {"error":"La corte rialzata esiste già: modifica il suo nodo."}
	var check: Dictionary=group.resize_proposal(group.layout_size())
	if check.has("error"): return check
	var low: Vector3=group.towers()[0].position; var high := low; var radius := Vector2.ZERO
	for tower in group.towers():
		low=low.min(tower.position); high=high.max(tower.position)
		radius=radius.max(Vector2(tower.width,tower.depth)*0.5)
	if high.x-low.x<16 or high.z-low.z<16: return {"error":"Il preset richiede almeno 16 m fra i centri delle torri."}
	for building in group.buildings():
		if not is_zero_approx(building.position.y): return {"error":"Quote già modificate: il preset non sovrascrive le posizioni manuali."}
	var front := high.z-radius.y; var rear := low.z-radius.y
	var positions := {}
	for building in group.buildings():
		if building in group.towers() and is_equal_approx(building.position.z,high.z): continue
		if building not in group.towers():
			var bounds: AABB=building.transform*AABB(Vector3(-building.width*0.5,0,-building.depth*0.5),Vector3(building.width,1,building.depth))
			if bounds.end.z>front or bounds.position.z<rear or bounds.position.x<low.x-radius.x or bounds.end.x>high.x+radius.x:
				return {"error":str(building.name)+": sposta l'edificio interamente nella corte posteriore prima di rialzarlo."}
		positions[group.get_path_to(building)]=building.position+Vector3.UP*1.2
	var court=preload("res://addons/house_builder/raised_courtyard.gd").new(); court.name="CorteRialzata"
	court.size=Vector2(high.x-low.x+radius.x*2,front-rear); court.position=Vector3((low.x+high.x)*0.5,0,(front+rear)*0.5)
	court.access_run=radius.y
	for path in positions: court.linked_buildings.append(NodePath("../"+str(path)))
	return {"court":court,"positions":positions}
