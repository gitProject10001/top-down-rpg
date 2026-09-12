@tool
extends RefCounted
## Rectangular subdivision + explicit adjacency graph. Coordinates are metres.
static func rect(record: Dictionary) -> Rect2:
	return Rect2(Vector2(record.position.x-record.dimensions.x*0.5,record.position.z-record.dimensions.z*0.5),Vector2(record.dimensions.x,record.dimensions.z))
static func room(id: String,bounds: Rect2,h: float,type: String) -> Dictionary:
	return {"id":id,"kind":0,"position":Vector3(bounds.get_center().x,0,bounds.get_center().y),"rotation":Vector3.ZERO,"dimensions":Vector3(bounds.size.x,h,bounds.size.y),"room_type":type}
static func subtract(a: Rect2,b: Rect2) -> Array[Rect2]:
	var overlap := a.intersection(b)
	if not overlap.has_area(): return [a]
	var result: Array[Rect2]=[]
	for r in [Rect2(a.position,Vector2(overlap.position.x-a.position.x,a.size.y)),Rect2(Vector2(overlap.end.x,a.position.y),Vector2(a.end.x-overlap.end.x,a.size.y)),Rect2(Vector2(overlap.position.x,a.position.y),Vector2(overlap.size.x,overlap.position.y-a.position.y)),Rect2(Vector2(overlap.position.x,overlap.end.y),Vector2(overlap.size.x,a.end.y-overlap.end.y))]:
		if r.size.x>0.01 and r.size.y>0.01: result.append(r)
	return result
static func rooms(plan: Node3D,floor_index: int,fixed: Array=[]) -> Array:
	var house=plan.house(); var h: float=plan.floor_height
	var bounds := Rect2(Vector2(-house.width*0.5+0.25,-house.depth*0.5+0.25),Vector2(house.width-0.5,house.depth-0.5))
	var rng := RandomNumberGenerator.new(); rng.seed=plan.seed_value+floor_index*7919
	var result: Array=fixed.duplicate(true)
	var free: Array[Rect2]=[bounds]
	var hall_center := 0.0
	for opening in house.openings:
		var o: Dictionary=house.resolved_opening(opening)
		if o.door and o.wall==0: hall_center=o.along; break
	var hall_half := 1.4 if plan.levels().size()>1 and house.width>=6 else 0.9
	var hall_min := maxf(bounds.position.x,hall_center-hall_half)
	var hall_max := minf(bounds.end.x,hall_center+hall_half)
	if hall_min-bounds.position.x<1.2: hall_min=bounds.position.x
	if bounds.end.x-hall_max<1.2: hall_max=bounds.end.x
	var hall := room("hall",Rect2(Vector2(hall_min,bounds.position.y),Vector2(hall_max-hall_min,bounds.size.y)),h,"ingresso")
	var has_hall := false
	for r in result:
		if r.id=="hall": hall=r; has_hall=true
	if not has_hall:
		var conflict := false
		for r in result:
			if rect(r).intersects(rect(hall)): conflict=true
		if not conflict: result.append(hall)
	for r in result:
		var next: Array[Rect2]=[]
		for region in free: next.append_array(subtract(region,rect(r)))
		free=next
	var desired: int=maxi(1,plan.requested_rooms-result.size())
	while free.size()<desired:
		var best := -1; var area := 0.0
		for i in free.size():
			if maxf(free[i].size.x,free[i].size.y)>=3.2 and free[i].get_area()>area: best=i; area=free[i].get_area()
		if best<0: break
		var r := free[best]; free.remove_at(best)
		var vertical := r.size.x>r.size.y
		var extent := r.size.x if vertical else r.size.y
		var cut := clampf(snappedf(extent*rng.randf_range(0.38,0.62),0.1),1.5,extent-1.5)
		if vertical:
			free.append(Rect2(r.position,Vector2(cut,r.size.y))); free.append(Rect2(r.position+Vector2(cut,0),Vector2(r.size.x-cut,r.size.y)))
		else:
			free.append(Rect2(r.position,Vector2(r.size.x,cut))); free.append(Rect2(r.position+Vector2(0,cut),Vector2(r.size.x,r.size.y-cut)))
	var used: Dictionary={}
	for r in result: used[r.id]=true
	var index := 0
	for r in free:
		while used.has("room_%d"%index): index+=1
		result.append(room("room_%d"%index,r,h,["soggiorno","cucina","camera","ripostiglio"][index%4])); index+=1
	if house.wing_enabled:
		var side := 1.0 if house.wing_side==0 else -1.0
		var center: Vector3=house.wing_transform().origin
		var extension := Rect2(Vector2(house.width*0.5-0.25 if side>0 else -house.width*0.5-house.wing_length+0.25,center.z-house.wing_span()*0.5+0.25),Vector2(house.wing_length,house.wing_span()-0.5))
		if not used.has("wing"): result.append(room("wing",extension,h,"soggiorno"))
	return result
static func shared(a: Rect2,b: Rect2) -> Dictionary:
	for edge in [a.position.x,a.end.x]:
		if absf(edge-b.position.x)<0.01 or absf(edge-b.end.x)<0.01:
			var low := maxf(a.position.y,b.position.y); var high := minf(a.end.y,b.end.y)
			if high-low>0.01: return {"a":Vector2(edge,low),"b":Vector2(edge,high)}
	for edge in [a.position.y,a.end.y]:
		if absf(edge-b.position.y)<0.01 or absf(edge-b.end.y)<0.01:
			var low := maxf(a.position.x,b.position.x); var high := minf(a.end.x,b.end.x)
			if high-low>0.01: return {"a":Vector2(low,edge),"b":Vector2(high,edge)}
	return {}
static func walls(room_records: Array,h: float) -> Array:
	var edges: Array=[]
	for i in room_records.size():
		for j in range(i+1,room_records.size()):
			var segment := shared(rect(room_records[i]),rect(room_records[j]))
			if segment.is_empty(): continue
			segment.merge({"i":i,"j":j,"door":false}); edges.append(segment)
	var reached: Dictionary={}
	for i in room_records.size():
		if room_records[i].id=="hall": reached[i]=true
	if reached.is_empty() and not room_records.is_empty(): reached[0]=true
	for iteration in room_records.size():
		for edge in edges:
			if edge.a.distance_to(edge.b)<1.35: continue
			if reached.has(edge.i)!=reached.has(edge.j): edge.door=true; reached[edge.i]=true; reached[edge.j]=true
	var result: Array=[]
	for edge in edges:
		var a: Vector2=edge.a; var b: Vector2=edge.b; var mid := (a+b)*0.5
		var ids := [str(room_records[edge.i].id),str(room_records[edge.j].id)]; ids.sort()
		result.append({"id":"wall_"+ids[0]+"_"+ids[1],"kind":1,"position":Vector3(mid.x,0,mid.y),"rotation":Vector3(0,-atan2(b.y-a.y,b.x-a.x),0),"dimensions":Vector3(a.distance_to(b),h,0.18),"has_door":edge.door,"door_width":1.2,"door_offset":0.0,"room_ids":PackedStringArray(ids)})
	return result
static func validate(room_records: Array,wall_records: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for i in room_records.size():
		var a := rect(room_records[i])
		if minf(a.size.x,a.size.y)<1.1: errors.append("Stanza troppo stretta: "+str(room_records[i].id))
		for j in range(i+1,room_records.size()):
			if a.intersection(rect(room_records[j])).get_area()>0.01: errors.append("Stanze sovrapposte")
	var connected: Dictionary={}
	if not room_records.is_empty(): connected[room_records[0].id]=true
	for iteration in room_records.size():
		for wall in wall_records:
			if not wall.get("has_door",false): continue
			var ids: PackedStringArray=wall.room_ids
			if connected.has(ids[0]) or connected.has(ids[1]): connected[ids[0]]=true; connected[ids[1]]=true
	for r in room_records:
		if not connected.has(r.id): errors.append("Stanza non raggiungibile: "+str(r.id))
	return errors
static func stair(plan: Node3D,room_records: Array) -> Dictionary:
	for room_record in room_records:
		if room_record.id!="hall": continue
		var r := rect(room_record)
		if r.size.x<2.5 or r.size.y<5.3: return {}
		return {"id":"stairs","kind":2,"position":Vector3(r.end.x-0.7,0,r.get_center().y),"rotation":Vector3.ZERO,"dimensions":Vector3(1.2,plan.floor_height,4.2)}
	return {}
static func clear_doors(walls: Array,obstacles: Array) -> bool:
	for wall in walls:
		if not wall.has_door: continue
		var length: float=wall.dimensions.x
		var direction := Vector2(cos(wall.rotation.y),-sin(wall.rotation.y))
		var center := Vector2(wall.position.x,wall.position.z)
		var found := false
		for amount in [0.0,-length*0.5+0.85,length*0.5-0.85]:
			var point: Vector2=center+direction*amount
			var blocked := false
			for obstacle in obstacles:
				if rect(obstacle).grow(0.45).has_point(point): blocked=true
			if not blocked:
				wall.door_offset=amount/(length*0.5); found=true; break
		if not found: return false
	return true
