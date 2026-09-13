@tool
extends Node3D
const House=preload("res://addons/house_builder/house.gd")
## Group of independently authored towers; links are stored on curtains.
@export var courtyard_entry := false
@export var entry_position := Vector3(8,0.15,4)

func primary_tower() -> Node3D:
	for child in get_children():
		if child.has_method("footprint_vertices"): return child
	return null
func curtains() -> Array:
	var result: Array=[]
	for tower in get_children():
		for child in tower.get_children():
			if child.has_method("fortification_host"): result.append(child)
	return result
func rebuild() -> void:
	for tower in get_children():
		if tower.has_method("rebuild"): tower.rebuild()

	for wall in curtains(): wall.rebuild()
	for tower in get_children():
		if tower.has_method("rebuild"): tower.rebuild()

func towers() -> Array:
	return get_children().filter(func(n): return n.has_method("footprint_vertices"))

func buildings() -> Array:
	return get_children().filter(func(n): return n is House)

func diagnostics() -> Array[Dictionary]:
	var issues: Array[Dictionary]=[]; var slots := {}; var degree := {}; var gates := 0
	var adjacency := {}
	for tower in towers(): degree[tower]=0; adjacency[tower]=[]
	for wall in curtains():
		var error: String=wall.connection_error()
		if not error.is_empty(): issues.append({"node":get_path_to(wall),"message":str(wall.get_parent().name)+" / "+str(wall.name)+": "+error})
		if wall.gate_enabled: gates+=1
		if not wall.connect_to_tower: continue
		for pair in [[wall.fortification_host(),wall.tower_face],[wall.destination(),wall.target_face]]:
			var tower=pair[0]
			if tower==null: continue
			if not degree.has(tower):
				issues.append({"node":get_path_to(wall),"message":"Destinazione fuori da questo gruppo: "+str(wall.name)}); continue
			degree[tower]+=1
			var key := str(tower.get_instance_id())+"/"+str(pair[1])
			if slots.has(key): issues.append({"node":get_path_to(wall),"message":str(tower.name)+": più cortine usano la faccia "+str(pair[1])+"."})
			slots[key]=true
	for wall in curtains():
		var a=wall.fortification_host(); var b=wall.destination()
		if wall.connect_to_tower and adjacency.has(a) and adjacency.has(b):
			adjacency[a].append(b); adjacency[b].append(a)
	if courtyard_entry:
		var seen := {}; var pending: Array=[]
		if not towers().is_empty(): pending.append(towers()[0])
		while not pending.is_empty():
			var tower=pending.pop_back()
			if seen.has(tower): continue
			seen[tower]=true; pending.append_array(adjacency[tower])
		if seen.size()!=towers().size(): issues.append({"node":NodePath("."),"message":"Il recinto è separato in gruppi non collegati."})
		for tower in degree:
			if degree[tower]!=2: issues.append({"node":get_path_to(tower),"message":str(tower.name)+": il recinto richiede due collegamenti; presenti "+str(degree[tower])+"."})
		if gates==0: issues.append({"node":NodePath("."),"message":"Il recinto non ha un portone di ingresso."})
	for building in buildings():
		if building in towers(): continue
		for volume in building.authored_volumes():
			var detail: String=volume.volume_error()
			if not detail.is_empty(): issues.append({"node":get_path_to(volume),"message":str(volume.name)+": "+detail})
		var error := courtyard_building_error(building)
		if not error.is_empty(): issues.append({"node":get_path_to(building),"message":str(building.name)+": "+error})
	return issues

func courtyard_building_error(building: Node3D) -> String:
	if towers().size()!=4: return "Verifica manualmente i passaggi: controllo corte disponibile per quattro torri."
	var low: Vector3=towers()[0].position; var high := low; var clearance := Vector2.ZERO
	for tower in towers():
		low=low.min(tower.position); high=high.max(tower.position)
		clearance=clearance.max(Vector2(tower.width,tower.depth)*0.5)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			var point: Vector3=building.transform*Vector3(x*building.width*0.5,0,z*building.depth*0.5)
			if point.x<low.x+clearance.x+1-0.01 or point.x>high.x-clearance.x-1+0.01 or point.z<low.z+clearance.y+1-0.01 or point.z>high.z-clearance.y-1+0.01:
				return "Edificio fuori dalla zona centrale con passaggio di 1 m: spostalo, riducilo o allarga il recinto."
	return ""

func layout_state() -> Dictionary:
	var positions := {}
	for tower in towers(): positions[get_path_to(tower)]=tower.position
	return {"positions":positions,"entry":entry_position}

func layout_size() -> Vector2:
	var list := towers()
	if list.is_empty(): return Vector2.ZERO
	var low: Vector3=list[0].position; var high := low
	for tower in list: low=low.min(tower.position); high=high.max(tower.position)
	return Vector2(high.x-low.x,high.z-low.z)

func resize_proposal(size: Vector2) -> Dictionary:
	var list := towers()
	if list.size()!=4: return {"error":"Questo controllo richiede un recinto rettangolare con quattro torri."}
	var low: Vector3=list[0].position; var high := low
	for tower in list: low=low.min(tower.position); high=high.max(tower.position)
	var corners := {}
	for tower in list:
		if not tower.basis.is_equal_approx(Basis.IDENTITY) or (not is_equal_approx(tower.position.x,low.x) and not is_equal_approx(tower.position.x,high.x)) or (not is_equal_approx(tower.position.z,low.z) and not is_equal_approx(tower.position.z,high.z)):
			return {"error":"La pianta è stata modificata liberamente e non è rettangolare: usa le trasformazioni delle singole torri."}
		corners[Vector2(tower.position.x,tower.position.z)]=true
	if corners.size()!=4 or size.x<=0 or size.y<=0: return {"error":"Dimensioni o disposizione delle torri non valide."}
	var state := layout_state()
	for tower in list:
		var position: Vector3=tower.position
		position.x=low.x if is_equal_approx(position.x,low.x) else low.x+size.x
		position.z=high.z if is_equal_approx(position.z,high.z) else high.z-size.y
		state.positions[get_path_to(tower)]=position
	for wall in curtains():
		var host=wall.fortification_host(); var target=wall.destination()
		if host==null or target==null or not state.positions.has(get_path_to(target)): return {"error":"Ripristina prima i collegamenti mancanti."}
		var a: Vector3=state.positions[get_path_to(host)]+host.wall_point(wall.tower_face,0,0)
		var b: Vector3=state.positions[get_path_to(target)]+target.wall_point(wall.target_face,0,0)
		var normal: Vector3=host.wall_normal(wall.tower_face); var gap := b-a; var distance := gap.dot(normal)
		if normal.dot(target.wall_normal(wall.target_face))>-0.999 or distance<1.8 or distance>19.8 or (gap-normal*distance).length()>0.03: return {"error":"Le dimensioni richieste non rispettano i raccordi: distanza libera fra facce 1.8–19.8 m."}
	state.entry.x=remap(entry_position.x,low.x,high.x,low.x,low.x+size.x)
	# Preserve the distance of an exterior spawn from the front edge.
	if entry_position.z<=high.z and entry_position.z>=low.z: state.entry.z=remap(entry_position.z,low.z,high.z,high.z-size.y,high.z)
	return state

func apply_layout(state: Dictionary) -> void:
	for path in state.positions:
		var node := get_node_or_null(path)
		if node: node.position=state.positions[path]
	entry_position=state.entry; rebuild()

func accessory_error(volume: Node3D) -> String:
	var host=volume.volume_host()
	var frame: Transform3D=host.transform*volume.transform
	var bounds: AABB=frame*AABB(Vector3(-volume.width*0.5,0,-volume.depth*0.5),Vector3(volume.width,1,volume.depth))
	for obstacle in towers()+curtains():
		var pose: Transform3D=obstacle.transform if obstacle in towers() else obstacle.get_parent().transform*obstacle.transform
		var other: AABB=pose*AABB(Vector3(-obstacle.width*0.5,0,-obstacle.depth*0.5),Vector3(obstacle.width,1,obstacle.depth))
		if bounds.grow(0.5).intersects(other): return "Corpo troppo vicino a torri o mura: spostalo o allarga la corte (margine 0.5 m)."
	return ""
