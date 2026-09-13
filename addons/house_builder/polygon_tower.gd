@tool
extends "res://addons/house_builder/volume.gd"
## First A07 footprint: eight planar faces, sharing the House opening pipeline.
func _init() -> void:
	attached=false; canopy_roof=2; battlements_enabled=true; archetype_id="tower"

func wall_count() -> int: return 8

func footprint_vertices() -> Array[Vector3]:
	var points: Array[Vector3]=[]
	for i in 8:
		var angle := (i-0.5)*TAU/8.0
		points.append(Vector3(sin(angle)*width*0.5/cos(PI/8),0,cos(angle)*depth*0.5/cos(PI/8)))
	return points

func wall_length(wall: int) -> float:
	var points := footprint_vertices()
	return points[posmod(wall,8)].distance_to(points[posmod(wall+1,8)])

func wall_normal(wall: int) -> Vector3:
	var points := footprint_vertices()
	return (points[posmod(wall+1,8)]-points[posmod(wall,8)]).normalized().cross(Vector3.UP)

func wall_point(wall: int,along: float,y: float,outset: float=0.0) -> Vector3:
	var points := footprint_vertices(); var a := points[posmod(wall,8)]; var b := points[posmod(wall+1,8)]
	return (a+b)*0.5+(b-a).normalized()*along+Vector3.UP*y+wall_normal(wall)*outset

func wall_exposed(wall: int,along: float,margin: float=0.0) -> bool:
	return wall>=0 and wall<8 and absf(along)+margin<=wall_length(wall)*0.5+0.001

func _wall_box(wall: int,along: float,y: float,w: float,h: float,thick: float,offset: float,mat: int) -> void:
	var tangent := (wall_point(wall,1,0)-wall_point(wall,0,0)).normalized()
	var frame := Transform3D(Basis(tangent,Vector3.UP,wall_normal(wall)),wall_point(wall,along,y,offset))
	var points: Array[Vector3]=[]
	for v in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:
		points.append(frame*(v*Vector3(w,h,thick)*0.5))
	for face in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]:
		_tri(points[face[0]],points[face[1]],points[face[2]],mat)
		_tri(points[face[0]],points[face[2]],points[face[3]],mat)

func _polygon_slab(bottom: float,top: float,mat: int,inset: float=0.0) -> void:
	var points := footprint_vertices()
	for i in 8:
		var a_normal := wall_normal(i); var b_normal := wall_normal(posmod(i-1,8))
		points[i]-=(a_normal+b_normal)*inset/(1.0+a_normal.dot(b_normal))
	for i in 8:
		var a := points[i]; var b := points[(i+1)%8]
		_tri(Vector3.UP*top,a+Vector3.UP*top,b+Vector3.UP*top,mat)
		_tri(Vector3.UP*bottom,b+Vector3.UP*bottom,a+Vector3.UP*bottom,mat)
		_tri(a+Vector3.UP*bottom,b+Vector3.UP*bottom,b+Vector3.UP*top,mat)
		_tri(a+Vector3.UP*bottom,b+Vector3.UP*top,a+Vector3.UP*top,mat)

func _build_shell() -> void:
	_polygon_slab(-0.09,0,3)
	for wall in 8:
		var length := wall_length(wall)
		_wall_box(wall,0,wall_height*0.5,length+0.1,wall_height,WALL_THICKNESS,-WALL_THICKNESS*0.5,0)
		for y in [0.14,wall_height-0.08]:
			_wall_box(wall,0,y,length+0.12,0.16,0.30,-0.12,2)
		for sign_value in [-1.0,1.0]:
			_wall_box(wall,sign_value*length*0.5,wall_height*0.5,0.13,wall_height,0.14,0.04,1)

func _build_roof_slab() -> void: _polygon_slab(wall_height,wall_height+0.18,2)
func _build_roof() -> ArrayMesh:
	var roof := _flat_roof(); var plan=get_node_or_null("InteriorPlan")
	if plan==null or plan.levels().is_empty(): return roof
	var cuts: Array=[]
	for e in plan.levels().back().get_children():
		if e.has_method("opening_planes") and e.kind==2 and e.roof_exit:
			var planes: Array=e.opening_planes()
			planes.append(Plane(Vector3.UP,effective_elevation()+0.01))
			planes.append(Plane(Vector3.DOWN,-wall_height+0.01))
			cuts.append(planes)
	if cuts.is_empty(): return roof
	var result := ArrayMesh.new(); MeshJoin.append(result,roof,Transform3D.IDENTITY,cuts)
	return result
func stair_edge_length() -> float:
	return wall_length(stair_wall())

func hit_wall(world_origin: Vector3,world_direction: Vector3) -> Dictionary:
	var origin := to_local(world_origin); var direction := global_basis.inverse()*world_direction
	var result := {}; var closest := INF
	for wall in 8:
		var normal := wall_normal(wall)
		if normal.dot(direction)>=-0.0001: continue
		var p=Plane(normal,wall_point(wall,0,0)).intersects_ray(origin,direction)
		if p==null or p.y<0 or p.y>wall_height: continue
		var tangent := (wall_point(wall,1,0)-wall_point(wall,0,0)).normalized()
		var along: float=(p-wall_point(wall,0,0)).dot(tangent)
		if not wall_exposed(wall,along): continue
		var distance := world_origin.distance_to(to_global(p))
		if distance<closest:
			closest=distance
			result={"house":self,"wall":wall,"u":along/(wall_length(wall)*0.5),"y":p.y,"position":to_global(p),"distance":distance}
	return result

func _get_configuration_warnings() -> PackedStringArray:
	if attached or wing_enabled or canopy_roof!=2 or structure_kind!=0:
		return PackedStringArray(["Torre ottagonale: usare corpo indipendente chiuso, tetto piano e nessuna ala. Le altre configurazioni non sono ancora supportate."])
	return super._get_configuration_warnings()

func contains_footprint(point: Vector3,margin: float=0.0) -> bool:
	for wall in 8:
		if wall_normal(wall).dot(point-wall_point(wall,0,0))>=-margin: return false
	return true

func stair_wall() -> int:
	var stairs := stair_component()
	return [0,2,6][stairs.side] if stairs else 0

func interior_floor_mesh(material: Material) -> ArrayMesh:
	var previous := _buffers
	_buffers=[]
	for i in 4:
		var buffer := SurfaceTool.new(); buffer.begin(Mesh.PRIMITIVE_TRIANGLES); _buffers.append(buffer)
	_polygon_slab(-0.05,0.05,0,0.20)
	var mesh := ArrayMesh.new(); _buffers[0].commit(mesh); mesh.surface_set_material(0,material)
	_buffers=previous
	return mesh

func cutaway_cutters(floor_base: float,storey_height: float) -> Array:
	var cuts: Array=[[Plane(Vector3.DOWN,-floor_base-storey_height)]]
	for wall in 8:
		var normal := wall_normal(wall)
		if normal.dot(Vector3(1,0,1))>0.1:
			cuts.append([Plane(-normal,-normal.dot(wall_point(wall,0,0))+0.4),Plane(Vector3.DOWN,-floor_base-0.8)])
	return cuts


func connection_spans(wall: int,spans: Array[Vector2]) -> Array[Vector2]:
	for child in get_children():
		if not child.has_method("fortification_host") or not child.connect_to_tower or child.tower_face!=wall or not child.connection_error().is_empty(): continue
		var half: float=child.depth*0.5-0.22
		var remaining: Array[Vector2]=[]
		for span in spans:
			if span.x < -half: remaining.append(Vector2(span.x,minf(span.y,-half)))
			if span.y > half: remaining.append(Vector2(maxf(span.x,half),span.y))
		spans=remaining
	return spans
