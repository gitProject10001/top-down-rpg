@tool
extends RefCounted
# A court is the shared empty space. Buildings occupy its outside edges, with
# independent stable seeds so editing one court does not reshuffle the others.
static func candidates(village: Node) -> Array:
	var result: Array=[]
	for group in village.guides(4):
		var points: PackedVector2Array=group.village_points()
		var clockwise := Geometry2D.is_polygon_clockwise(points)
		for edge in points.size():
			var a := points[edge]; var b := points[(edge+1)%points.size()]
			var tangent := (b-a).normalized()
			var outward := Vector2(tangent.y,-tangent.x)*( -1.0 if clockwise else 1.0)
			var count := maxi(1,floori(a.distance_to(b)/11.0))
			for slot in count:
				var id := "%s_court_%d_%d"%[group.stable_id,edge,slot]
				var rng := RandomNumberGenerator.new(); rng.seed=hash(str(village.seed_value)+id)
				var small: bool= rng.randf()<0.3 and group.building_type!=1
				var size := Vector2(rng.randf_range(3.2,4.5),rng.randf_range(3.8,5.5)) if small else Vector2(rng.randf_range(5.5,9),rng.randf_range(6,10))
				var front := -outward
				var center := a.lerp(b,(slot+rng.randf_range(0.35,0.65))/count)+outward*(size.y*0.5+rng.randf_range(1.0,2.5))
				var pose := Transform3D(Basis(Vector3.UP,atan2(front.x,front.y)),Vector3(center.x,0,center.y))
				result.append({"id":id,"pose":pose,"size":size,"seed":rng.randi(),"group":group})
	return result

# Grid routing is used only at authoring time. Saved lots contain ordinary paths.
static func route(village: Node,pose: Transform3D,request: Resource,occupied: Array,boundary: PackedVector2Array,group_id: String="") -> PackedVector3Array:
	var size: Vector2=request.footprint
	var normal: Vector3=[Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT][request.entrance_side]
	var door := normal*(size.y*0.5 if request.entrance_side<2 else size.x*0.5)
	var approach: Vector3=pose*(door+normal*1.5)
	var obstacles: Array=occupied.duplicate(); obstacles.append(village.footprint(pose,size))
	var expanded: Array=[]
	for polygon in obstacles: expanded.append_array(Geometry2D.offset_polygon(polygon,0.85))
	var bounds := Rect2(boundary[0],Vector2.ZERO)
	for p in boundary: bounds=bounds.expand(p)
	# Keep authoring work bounded even on a large perimeter.
	var cell := maxf(1.0,ceilf(maxf(bounds.size.x,bounds.size.y)/150.0))
	var grid := AStarGrid2D.new(); grid.region=Rect2i(Vector2i(floori(bounds.position.x/cell),floori(bounds.position.y/cell)),Vector2i(ceili(bounds.size.x/cell)+2,ceili(bounds.size.y/cell)+2))
	grid.cell_size=Vector2.ONE*cell; grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES; grid.update()
	for x in range(grid.region.position.x,grid.region.end.x):
		for y in range(grid.region.position.y,grid.region.end.y):
			var p := Vector2(x,y)*cell
			var solid := not Geometry2D.is_point_in_polygon(p,boundary)
			for polygon in expanded:
				if Geometry2D.is_point_in_polygon(p,polygon): solid=true; break
			grid.set_point_solid(Vector2i(x,y),solid)
	var start := Vector2i((Vector2(approach.x,approach.z)/cell).round())
	if not grid.is_in_boundsv(start) or grid.is_point_solid(start): return PackedVector3Array()
	var hub := Vector2(approach.x,approach.z)
	for group in village.guides(4):
		if group.stable_id==group_id:
			var points: PackedVector2Array=group.village_points(); hub=Vector2.ZERO
			for p in points: hub+=p
			hub/=points.size()
	var hub_cell := Vector2i((hub/cell).round())
	if not grid.is_in_boundsv(hub_cell) or grid.is_point_solid(hub_cell): return PackedVector3Array()
	var to_hub := grid.get_point_path(start,hub_cell)
	if to_hub.is_empty(): return PackedVector3Array()
	var goals: Array=[]
	for road in village.guides(1):
		var points: PackedVector2Array=road.village_points()
		for i in range(points.size()-1):
			var p := Geometry2D.get_closest_point_to_segment(hub,points[i],points[i+1])
			goals.append(p)
	goals.sort_custom(func(a,b): return a.distance_squared_to(hub)<b.distance_squared_to(hub))
	for goal in goals:
		var end := Vector2i((goal/cell).round())
		if not grid.is_in_boundsv(end) or grid.is_point_solid(end): continue
		var from_hub := grid.get_point_path(hub_cell,end)
		if from_hub.is_empty(): continue
		var path := to_hub.duplicate(); var checkpoint := path.size()-1
		path[0]=Vector2(approach.x,approach.z); path[checkpoint]=hub
		for i in range(1,from_hub.size()): path.append(from_hub[i])
		path[-1]=goal
		var smooth := PackedVector2Array([path[0]]); var index := 0
		while index<path.size()-1:
			var next := index+1
			for j in range(checkpoint if index<checkpoint else path.size()-1,index,-1):
				var segment := PackedVector3Array([Vector3(path[index].x,0,path[index].y),Vector3(path[j].x,0,path[j].y)])
				var clear := true
				for shape in village.access_shapes(Transform3D.IDENTITY,segment):
					if not village.inside(shape,boundary): clear=false; break
					for polygon in obstacles:
						if not Geometry2D.intersect_polygons(shape,polygon).is_empty(): clear=false; break
				if clear: next=j; break
			index=next; smooth.append(path[index])
		var result := PackedVector3Array(); var inverse := pose.affine_inverse()
		for i in range(smooth.size()-1,-1,-1): result.append(inverse*Vector3(smooth[i].x,0,smooth[i].y))
		result.append(door)
		return result
	return PackedVector3Array()
