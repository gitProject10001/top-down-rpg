@tool
extends RefCounted

static func ribbon(points: PackedVector2Array,widths: PackedFloat32Array,base: float=3.0) -> Array:
	var result: Array=[]
	for i in range(points.size()-1):
		var n := (points[i+1]-points[i]).normalized().orthogonal()
		var a := widths[i]*0.5 if i<widths.size() else base*0.5
		var b := widths[i+1]*0.5 if i+1<widths.size() else base*0.5
		result.append(PackedVector2Array([points[i]+n*a,points[i+1]+n*b,points[i+1]-n*b,points[i]-n*a]))
	# Round joins close the outside wedges at bends, using the same footprint
	# for painting and collision validation.
	for i in points.size():
		var radius := widths[i]*0.5 if i<widths.size() else base*0.5
		var circle := PackedVector2Array()
		for j in 12: circle.append(points[i]+Vector2(cos(TAU*j/12),sin(TAU*j/12))*radius)
		result.append(circle)
	return result

static func junctions(roads: Array) -> Array:
	var result: Array=[]
	for a in roads.size():
		for b in range(a+1,roads.size()):
			var first: PackedVector2Array=roads[a].village_points(); var second: PackedVector2Array=roads[b].village_points()
			for i in range(first.size()-1):
				for j in range(second.size()-1):
					var point=Geometry2D.segment_intersects_segment(first[i],first[i+1],second[j],second[j+1])
					if point==null: continue
					var wa: PackedFloat32Array=roads[a].effective_widths(); var wb: PackedFloat32Array=roads[b].effective_widths()
					var width_a := lerpf(wa[i],wa[i+1],first[i].distance_to(point)/maxf(0.001,first[i].distance_to(first[i+1])))
					var width_b := lerpf(wb[j],wb[j+1],second[j].distance_to(point)/maxf(0.001,second[j].distance_to(second[j+1])))
					var circle := PackedVector2Array()
					for k in 16: circle.append(point+Vector2(cos(TAU*k/16),sin(TAU*k/16))*maxf(width_a,width_b)*0.65)
					result.append(circle)
	return result

static func hub(group: Node) -> Vector2:
	var result := Vector2.ZERO
	for p in group.village_points(): result+=p
	return result/group.points.size()

static func world_path(record: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in record.access:
		var q: Vector3=record.transform*p; points.append(Vector2(q.x,q.z))
	return points

static func shared(village: Node,records: Array,use_overrides: bool=true) -> Array:
	var result: Array=[]
	for group in village.guides(4):
		var center := hub(group)
		for record in records:
			if record.get("group","")!=group.stable_id: continue
			var points := world_path(record); var index := -1
			for i in points.size():
				if points[i].distance_to(center)<0.1: index=i; break
			if index<1: continue
			points=points.slice(0,index+1)
			var widths := PackedFloat32Array(); widths.resize(points.size()); widths.fill(1.4)
			widths[0]=2.4; widths[-1]=2.8
			if not use_overrides and record.has("shared_widths") and record.shared_widths.size()==points.size(): widths=record.shared_widths.duplicate()
			var override: Node=null
			for guide in village.guides(5):
				if use_overrides and guide.group_id==group.stable_id: override=guide; break
			if override:
				points=override.village_points(); widths=override.effective_widths()
				if points.size()>0 and points[-1].distance_to(center)>0.05: points.append(center); widths.append(widths[-1])
			else:
				# Auto widening yields to existing buildings; manual widths report conflicts.
				for attempt in 4:
					if clearance(village,records,points,widths).is_empty(): break
					for i in widths.size(): widths[i]=maxf(1.2,widths[i]-0.5)
			result.append({"group":group.stable_id,"name":str(group.name),"points":points,"widths":widths,"guide":override,"issue_node":group})
			break
	return result

static func clearance(village: Node,records: Array,points: PackedVector2Array,widths: PackedFloat32Array) -> String:
	for shape in ribbon(points,widths,1.4):
		if not village.inside(shape,village.guides(0)[0].village_points()): return "Il percorso esce dal perimetro."
		for r in records:
			var polygon: PackedVector2Array=r.node.polygon() if r.has("node") and is_instance_valid(r.node) else village.footprint(r.transform,r.request.footprint)
			if not Geometry2D.intersect_polygons(shape,polygon).is_empty(): return "Il percorso invade la casa "+str(r.id)+". Riduci la larghezza o sposta i punti."
	return ""

static func unify(village: Node,records: Array) -> String:
	var assigned := PackedStringArray()
	for guide in village.guides(5):
		if guide.points.size()<2: return "Percorso incompleto: "+str(guide.name)
		if not village.guides(4).any(func(group): return group.stable_id==guide.group_id): return "Percorso senza corte valida: "+str(guide.name)
		if guide.group_id in assigned: return "Due percorsi manuali assegnati alla stessa corte: "+guide.group_id
		assigned.append(guide.group_id)
	var routes := shared(village,records)
	for record in records:
		if not record.get("group","").is_empty() and not routes.any(func(route): return route.group==record.group): return "Rigenera la corte "+record.group+": manca il collegamento al suo centro."
	for route in routes:
		if route.points.size()<2: return route.name+": aggiungi almeno due punti al percorso."
		var connected := false
		for shape in village.road_shapes():
			if Geometry2D.is_point_in_polygon(route.points[0],shape): connected=true; break
		if not connected: return route.name+": il primo punto del percorso deve essere sulla strada."
		var error := clearance(village,records,route.points,route.widths)
		if not error.is_empty(): return route.name+": "+error
		var center: Vector2=route.points[-1]
		for record in records:
			if record.get("group","")!=route.group: continue
			var points := world_path(record); var index := -1
			for i in points.size():
				if points[i].distance_to(center)<0.1: index=i; break
			if index<0: return "Rigenera il gruppo "+route.name+": la corte non coincide con il percorso conservato."
			var updated: PackedVector2Array=route.points.duplicate()
			updated.append_array(points.slice(index+1))
			var local := PackedVector3Array(); var inverse: Transform3D=record.transform.affine_inverse()
			for p in updated: local.append(inverse*Vector3(p.x,0,p.y))
			record.access=local; record.shared_widths=route.widths.duplicate()
	return ""

static func validate(village: Node,records: Array) -> String:
	for road in village.guides(1):
		if road.points.size()<2: return "Strada incompleta: "+str(road.name)
		for polygon in ribbon(road.village_points(),road.effective_widths()):
			for record in records:
				var house: PackedVector2Array=record.node.polygon() if record.has("node") and is_instance_valid(record.node) else village.footprint(record.transform,record.request.footprint)
				if not Geometry2D.intersect_polygons(polygon,house).is_empty(): road.network_issue=true; road.update_gizmos(); return "La strada "+str(road.name)+" invade una casa. Riduci la larghezza o sposta il percorso."
	for polygon in junctions(village.guides(1)):
		for record in records:
			var house: PackedVector2Array=record.node.polygon() if record.has("node") and is_instance_valid(record.node) else village.footprint(record.transform,record.request.footprint)
			if not Geometry2D.intersect_polygons(polygon,house).is_empty(): return "L'allargamento dell'incrocio invade una casa: sposta il percorso o riduci le larghezze."
	var paths: Array=[]
	for guide in village.guides(1):
		paths.append({"name":str(guide.name),"points":guide.village_points(),"widths":guide.effective_widths(),"guide":guide})
	paths.append_array(shared(village,records))
	if paths.is_empty(): return "Manca una strada d'ingresso."
	var start := 0
	for i in village.guides(1).size():
		if village.guides(1)[i].stable_id==village.entry_road_id: start=i
	var regions: Array=[]
	for path in paths:
		var widths: PackedFloat32Array=path.widths.duplicate()
		for i in widths.size(): widths[i]=maxf(0.2,widths[i]-0.8)
		regions.append(ribbon(path.points,widths))
	var reached: Array=[start]; var queue: Array=[start]
	while not queue.is_empty():
		var current: int=queue.pop_front()
		for i in paths.size():
			if i in reached: continue
			var joined := false
			for a in regions[current]:
				for b in regions[i]:
					if not Geometry2D.intersect_polygons(a,b).is_empty(): joined=true; break
				if joined: break
			if joined: reached.append(i); queue.append(i)
	var missing := PackedStringArray()
	for i in paths.size():
		if i not in reached:
			missing.append(paths[i].name)
			var node: Node=paths[i].get("guide",paths[i].get("issue_node"))
			if node==null: node=paths[i].get("issue_node")
			if node: node.network_issue=true; node.update_gizmos()
	return "Non raggiungibili dall'ingresso ("+str(paths[start].name)+"): "+", ".join(missing) if not missing.is_empty() else ""
