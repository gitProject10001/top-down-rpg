@tool
extends Node3D
const Guide=preload("res://addons/village_builder/guide.gd")
const Lot=preload("res://addons/village_builder/lot.gd")
const Request=preload("res://addons/house_builder/building_request.gd")
@export var seed_value := 1047
@export_enum("Casa popolana","Bottega","Casa benestante") var building_type := 0
@export_range(1,3) var storeys := 1
@export_range(1,40) var max_houses := 16
@export_range(1,5,0.25) var setback := 1.5
@export_range(-180,180,1) var fixed_camera_yaw := 45.0
@export_storage var known_ids: PackedStringArray=[]
@export_storage var deleted_ids: PackedStringArray=[]
var report := ""
var failed := false
var retired: Dictionary={}
const DENSITY_CELL := 2.0
@export_storage var density_state: Dictionary={"base":1.0,"cells":{}}
func density_at(point: Vector2) -> float:
	var grid := point/DENSITY_CELL-Vector2.ONE*0.5
	var cell := Vector2i(floori(grid.x),floori(grid.y)); var fraction := grid-Vector2(cell)
	var cells: Dictionary=density_state.get("cells",{})
	var base: float=density_state.get("base",1.0)
	var a := lerpf(cells.get(cell,base),cells.get(cell+Vector2i.RIGHT,base),fraction.x)
	var b := lerpf(cells.get(cell+Vector2i.DOWN,base),cells.get(cell+Vector2i.ONE,base),fraction.x)
	return clampf(lerpf(a,b,fraction.y),0,1)
func paint_density(point: Vector2,radius: float,target: float) -> void:
	var next := density_state.duplicate(true); var cells: Dictionary=next.cells
	var low := Vector2i(floori((point.x-radius)/DENSITY_CELL),floori((point.y-radius)/DENSITY_CELL))
	var high := Vector2i(ceili((point.x+radius)/DENSITY_CELL),ceili((point.y+radius)/DENSITY_CELL))
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell := Vector2i(x,y); var distance := ((Vector2(cell)+Vector2.ONE*0.5)*DENSITY_CELL).distance_to(point)
			if distance>=radius: continue
			var weight := clampf((1.0-distance/radius)*2,0,1)
			cells[cell]=lerpf(cells.get(cell,next.base),clampf(target,0,1),weight)
	density_state=next
func guides(kind: int) -> Array:
	return get_children().filter(func(n): return n is Guide and n.kind==kind)
func lots() -> Array: return get_children().filter(func(n): return n is Lot)
func snapshot() -> Array:
	return lots().map(func(n): return {"id":n.stable_id,"transform":n.transform,"request":n.request,"zone":n.zone_id,"locked":n.locked,"node":n,"baseline_pose":n.baseline_pose,"baseline_house":n.baseline_house.duplicate(true),"access":n.access_path})
func entrance_wall(pose: Transform3D) -> int:
	var toward_camera := Vector3(sin(deg_to_rad(fixed_camera_yaw)),0,cos(deg_to_rad(fixed_camera_yaw)))
	var best := -INF; var chosen := 0
	for side in 4:
		var normal: Vector3=global_basis*pose.basis*[Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT][side]
		var score := normal.dot(toward_camera)
		if score>best+0.001: best=score; chosen=side
	return chosen
func access_points(size: Vector2,side: int,road_width: float) -> PackedVector3Array:
	var front := size.y*0.5+setback*0.5
	var points := PackedVector3Array([Vector3(0,0,size.y*0.5+setback+road_width*0.5),Vector3(0,0,front)])
	if side==0: points.append(Vector3(0,0,size.y*0.5)); return points
	var sign_value := -1.0 if side==3 else 1.0
	var edge := sign_value*(size.x*0.5+0.85)
	points.append(Vector3(edge,0,front))
	if side==1:
		points.append(Vector3(edge,0,-size.y*0.5-0.85)); points.append(Vector3(0,0,-size.y*0.5-0.85)); points.append(Vector3(0,0,-size.y*0.5))
	else: points.append(Vector3(edge,0,0)); points.append(Vector3(sign_value*size.x*0.5,0,0))
	return points
static func access_shapes(pose: Transform3D,points: PackedVector3Array) -> Array:
	var result: Array=[]
	for i in range(points.size()-1):
		var a := pose*points[i]; var b := pose*points[i+1]; var n := (b-a).normalized().cross(Vector3.UP)*0.6
		result.append(PackedVector2Array([Vector2((a+n).x,(a+n).z),Vector2((b+n).x,(b+n).z),Vector2((b-n).x,(b-n).z),Vector2((a-n).x,(a-n).z)]))
	return result
static func inside(poly: PackedVector2Array,boundary: PackedVector2Array) -> bool:
	if boundary.size()<3: return false
	for p in poly:
		if not Geometry2D.is_point_in_polygon(p,boundary): return false
	for i in poly.size():
		for j in boundary.size():
			if Geometry2D.segment_intersects_segment(poly[i],poly[(i+1)%poly.size()],boundary[j],boundary[(j+1)%boundary.size()])!=null: return false
	return true
static func footprint(pose: Transform3D,size: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var q := pose*Vector3(p.x*size.x/2,0,p.y*size.y/2); result.append(Vector2(q.x,q.z))
	return result
func road_shapes() -> Array:
	var result: Array=[]
	for road in guides(1):
		var points: PackedVector2Array=road.village_points()
		for i in range(points.size()-1):
			var a := points[i]; var b := points[i+1]; var normal: Vector2=(b-a).normalized().orthogonal()*road.road_width*0.5
			result.append(PackedVector2Array([a+normal,b+normal,b-normal,a-normal]))
	return result
func propose() -> Array:
	failed=true
	var before := snapshot()
	if guides(0).size()!=1 or guides(1).is_empty():
		report="Servono un perimetro e almeno una strada. Il perimetro è edificabile per default."; return before
	var boundary: PackedVector2Array=guides(0)[0].village_points()
	if boundary.size()<3 or Geometry2D.triangulate_polygon(boundary).is_empty(): report="Il perimetro deve essere un poligono semplice, senza incroci."; return before
	for zone in guides(2)+guides(3):
		if zone.points.size()<3 or Geometry2D.triangulate_polygon(zone.village_points()).is_empty(): report="Zona non valida: "+str(zone.name); return before
	for road in guides(1):
		if road.points.size()<2: report="Strada incompleta: "+str(road.name); return before
		for i in range(road.points.size()-1):
			if road.points[i].distance_to(road.points[i+1])<0.5: report="Due punti della strada coincidono: "+str(road.name); return before
	var present := PackedStringArray()
	for lot in lots(): present.append(lot.stable_id)
	for id in known_ids:
		if id not in present and id not in deleted_ids: deleted_ids.append(id)
	for id in present: deleted_ids.erase(id)
	var result: Array=[]; var occupied: Array=[]; var reserved_access: Array=[]; var roads := road_shapes()
	for lot in lots():
		if not lot.protected_edit(): continue
		var poly: PackedVector2Array=lot.polygon()
		if not inside(poly,boundary): report="Il perimetro esclude un lotto modificato: "+str(lot.name); return before
		for zone in guides(3):
			if not Geometry2D.intersect_polygons(poly,zone.village_points()).is_empty(): report="L'area non edificabile invade il lotto protetto "+str(lot.name)+". Sposta il lotto o modifica l'area."; return before
		for obstacle in occupied+reserved_access:
			if not Geometry2D.intersect_polygons(poly,obstacle).is_empty(): report="Il lotto protetto "+str(lot.name)+" occupa un'altra casa o il suo accesso."; return before
		for road in roads:
			if not Geometry2D.intersect_polygons(poly,road).is_empty(): report="La strada attraversa il lotto protetto "+str(lot.name)+". Sposta la strada o il lotto."; return before
		if not lot.access_path.is_empty():
			var entrance: Vector3=lot.transform*lot.access_path[0]
			var connected := false
			for road in roads:
				if Geometry2D.is_point_in_polygon(Vector2(entrance.x,entrance.z),road): connected=true; break
			if not connected: report="La strada non raggiunge più il percorso del lotto protetto "+str(lot.name)+". Ripristina il collegamento."; return before
		var protected_paths := access_shapes(lot.transform,lot.access_path)
		for path in protected_paths:
			if not inside(path,boundary): report="Il percorso del lotto protetto esce dal perimetro: "+str(lot.name); return before
			for obstacle in occupied:
				if not Geometry2D.intersect_polygons(path,obstacle).is_empty(): report="Accesso ostruito al lotto protetto "+str(lot.name); return before
		occupied.append(poly)
		reserved_access.append_array(protected_paths)
		result.append(before.filter(func(r): return r.id==lot.stable_id)[0])
	var skipped := 0; var density_skipped := 0; var excluded_count := 0
	for road in guides(1):
		var points: PackedVector2Array=road.village_points()
		for segment in range(points.size()-1):
			var a := points[segment]; var b := points[segment+1]; var direction := (b-a).normalized(); var normal := Vector2(-direction.y,direction.x)
			var slots := floori(a.distance_to(b)/10.0)
			for slot in slots:
				for side in [-1,1]:
					if result.size()>=max_houses: break
					var id := "%s_%d_%d_%d"%[road.stable_id,segment,slot,side]
					if id in deleted_ids or result.any(func(r): return r.id==id): continue
					var rng := RandomNumberGenerator.new(); rng.seed=hash(str(seed_value)+id)
					var width := snappedf(rng.randf_range(4.5,6.5),0.1); var depth := snappedf(rng.randf_range(5.5,8.0),0.1)
					var along := a+direction*((slot+0.5)*a.distance_to(b)/slots)
					var center: Vector2=along+normal*side*(road.road_width*0.5+setback+depth*0.5)
					var front: Vector2=-normal*side
					var pose := Transform3D(Basis(Vector3.UP,atan2(front.x,front.y)),Vector3(center.x,0,center.y))
					var poly := footprint(pose,Vector2(width,depth))
					if not inside(poly,boundary): skipped+=1; continue
					var excluded := false
					for zone in guides(3):
						if not Geometry2D.intersect_polygons(poly,zone.village_points()).is_empty(): excluded=true; break
					if excluded: skipped+=1; excluded_count+=1; continue
					var chosen: Node=self
					for zone in guides(2):
						if inside(poly,zone.village_points()): chosen=zone; break
					var density_rng := RandomNumberGenerator.new(); density_rng.seed=hash(str(seed_value)+id+"density")
					if density_rng.randf()>=density_at(center): density_skipped+=1; continue
					var blocked := false
					var margin_poly := footprint(pose,Vector2(width+1,depth+1))
					for obstacle in occupied+roads+reserved_access:
						if not Geometry2D.intersect_polygons(margin_poly,obstacle).is_empty(): blocked=true; break
					if blocked: skipped+=1; continue
					var request := Request.new(); request.footprint=Vector2(width,depth); request.seed_value=rng.randi(); request.building_type=chosen.building_type; request.storeys=chosen.storeys
					request.entrance_side=entrance_wall(pose)
					var access := access_points(request.footprint,request.entrance_side,road.road_width)
					var paths := access_shapes(pose,access)
					for path in paths:
						if not inside(path,boundary): blocked=true; break
						for obstacle in occupied:
							if not Geometry2D.intersect_polygons(path,obstacle).is_empty(): blocked=true; break
					if blocked: skipped+=1; continue
					result.append({"id":id,"transform":pose,"request":request,"zone":chosen.stable_id if chosen!=self else "","locked":false,"access":access}); occupied.append(poly); reserved_access.append_array(paths)
	if result.is_empty() and density_skipped==0 and excluded_count==0: report="Nessun lotto disponibile: allarga il perimetro lungo la strada o riduci la distanza dalla strada."; return before
	failed=false; report="%d lotti; %d posizioni escluse, %d escluse dalla densità. Case modificate conservate."%[result.size(),skipped,density_skipped]
	return result
func owned(node: Node) -> void:
	if owner: node.owner=owner
	for child in node.get_children(): owned(child)
func apply(records: Array) -> void:
	var existing: Dictionary={}
	for lot in lots(): existing[lot.stable_id]=lot
	for r in records:
		var lot: Node3D=r.get("node")
		if lot==null and existing.has(r.id) and existing[r.id].request.data()==r.request.data(): lot=existing[r.id]
		if lot==null:
			lot=Lot.new(); lot.stable_id=r.id; lot.name="Lotto_"+r.id; lot.request=r.request
			var house: Node3D=r.request.create_house(); lot.add_child(house)
			lot.baseline_house=lot.house_state(); lot.baseline_pose=r.transform
		r.node=lot
	for lot in lots():
		if not records.any(func(r): return r.node==lot): remove_child(lot); retired[lot.get_instance_id()]=lot
	for r in records:
		var lot: Node3D=r.node
		if lot.get_parent()==null: retired.erase(lot.get_instance_id()); add_child(lot,true); owned(lot)
		lot.transform=r.transform; lot.zone_id=r.zone; lot.locked=r.locked
		lot.access_path=r.get("access",PackedVector3Array()); lot.rebuild_access()
		lot.baseline_pose=r.get("baseline_pose",r.transform)
		if r.has("baseline_house"): lot.baseline_house=r.baseline_house.duplicate(true)
	known_ids=PackedStringArray(records.map(func(r): return str(r.id)))
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		for node in retired.values():
			if is_instance_valid(node): node.free()
