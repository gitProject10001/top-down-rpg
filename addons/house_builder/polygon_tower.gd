@tool
extends "res://addons/house_builder/volume.gd"
## Segmented round/prismatic footprint, sharing the House opening pipeline.
@export_enum("8 facce:8", "12 facce:12", "16 facce:16") var face_count := 8:
	set(value):
		if value not in [8,12,16] or value==face_count: return
		if not custom_outline.is_empty(): push_warning("Ripristina la sagoma regolare prima di cambiare numero di facce."); return
		# Face indices are attachment anchors: never silently reassign authored openings.
		if is_inside_tree() and (not openings.is_empty() or not attached_components().is_empty() or get_node_or_null("InteriorPlan")!=null or get_child_count()>0):
			push_warning("Scegli il numero di facce prima di aggiungere aperture, interni o componenti. Usa una nuova torre per cambiare topologia.")
			return
		face_count=value; request_rebuild()
@export var edit_outline := false:
	set(value): edit_outline=value; if is_inside_tree(): update_gizmos()
## Normalized X/Z points: scaled by Width/Depth; empty uses the regular footprint.
@export var custom_outline := PackedVector2Array():
	set(value):
		var issue := outline_error(value)
		if issue.is_empty() and is_inside_tree(): issue=outline_attachment_error(value)
		if not issue.is_empty(): push_warning(issue); return
		custom_outline=value.duplicate(); request_rebuild()
func outline_error(points: PackedVector2Array) -> String:
	if points.is_empty(): return ""
	if points.size()!=face_count: return "La sagoma deve conservare %d vertici e l'ordine delle facce."%face_count
	for i in points.size():
		var a := points[i]; var b := points[(i+1)%points.size()]
		if not a.is_finite() or maxf(absf(a.x),absf(a.y))>0.75: return "Vertici finiti entro ±0.75 delle dimensioni della torre."
		var edge := b-a
		if edge.length()<0.08: return "Due vertici sono troppo vicini."
		# Clockwise XZ contour, with the origin strictly inside each half-plane.
		if edge.cross(-a)>-0.08*edge.length(): return "Mantieni il centro dentro la sagoma, con margine per muri e solai."
		for j in points.size():
			if j==i or j==(i+1)%points.size(): continue
			if edge.cross(points[j]-a)>=-0.00001: return "La sagoma deve essere convessa, senza incroci o vertici allineati; conserva l'ordine originale."
	return ""
func outline_attachment_error(points: PackedVector2Array) -> String:
	var shape := regular_outline() if points.is_empty() else points
	for opening in all_openings():
		var wall := int(opening.get("wall",0))
		if wall<0 or wall>=shape.size(): return "Un'apertura usa una faccia inesistente."
		var delta := (shape[(wall+1)%shape.size()]-shape[wall])*Vector2(width,depth)
		var requested := float(opening.get("width",1.0 if opening.get("kind","")=="door" else 0.85))
		if delta.length()<requested+0.4: return "Faccia %d troppo stretta per l'apertura esistente: sposta o riduci prima l'apertura."%wall
	return ""
func regular_outline() -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in face_count:
		var angle := (i-0.5)*TAU/float(face_count)
		result.append(Vector2(sin(angle),cos(angle))*0.5/cos(PI/float(face_count)))
	return result
@export_enum("Terrazza", "Conico", "Cupola") var tower_roof := 0:
	set(value):
		if value!=0 and is_inside_tree() and not conical_access_error().is_empty():
			push_warning(conical_access_error()); return
		tower_roof=value; request_rebuild()
func conical_access_error() -> String:
	var stairs := stair_component()
	if stairs and stairs.enabled: return "Disattiva la scala esterna al tetto prima di scegliere una copertura chiusa."
	var plan=get_node_or_null("InteriorPlan")
	if plan:
		for level in plan.levels():
			for element in level.get_children():
				if element.get("roof_exit")==true: return "Rimuovi o disattiva l'uscita sul tetto della scala interna prima di scegliere una copertura chiusa."
	return ""
func roof_is_walkable() -> bool: return tower_roof==0
func roof_access_error() -> String:
	if tower_roof!=0: return "La copertura chiusa non è una terrazza praticabile."
	return super.roof_access_error()
func roof_top() -> float:
	return wall_height+roof_height if tower_roof!=0 else super.roof_top()

func _init() -> void:
	attached=false; canopy_roof=2; battlements_enabled=true; archetype_id="tower"

func wall_count() -> int: return face_count

func footprint_vertices() -> Array[Vector3]:
	var points: Array[Vector3]=[]
	var outline := custom_outline if not custom_outline.is_empty() else regular_outline()
	for point in outline: points.append(Vector3(point.x*width,0,point.y*depth))
	return points

func wall_length(wall: int) -> float:
	var points := footprint_vertices()
	return points[posmod(wall,wall_count())].distance_to(points[posmod(wall+1,wall_count())])

func wall_normal(wall: int) -> Vector3:
	var points := footprint_vertices()
	return (points[posmod(wall+1,wall_count())]-points[posmod(wall,wall_count())]).normalized().cross(Vector3.UP)

func wall_point(wall: int,along: float,y: float,outset: float=0.0) -> Vector3:
	var points := footprint_vertices(); var a := points[posmod(wall,wall_count())]; var b := points[posmod(wall+1,wall_count())]
	return (a+b)*0.5+(b-a).normalized()*along+Vector3.UP*y+wall_normal(wall)*outset

func wall_exposed(wall: int,along: float,margin: float=0.0) -> bool:
	return wall>=0 and wall<wall_count() and absf(along)+margin<=wall_length(wall)*0.5+0.001

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
	for i in wall_count():
		var a_normal := wall_normal(i); var b_normal := wall_normal(posmod(i-1,wall_count()))
		points[i]-=(a_normal+b_normal)*inset/(1.0+a_normal.dot(b_normal))
	for i in wall_count():
		var a := points[i]; var b := points[(i+1)%wall_count()]
		_tri(Vector3.UP*top,a+Vector3.UP*top,b+Vector3.UP*top,mat)
		_tri(Vector3.UP*bottom,b+Vector3.UP*bottom,a+Vector3.UP*bottom,mat)
		_tri(a+Vector3.UP*bottom,b+Vector3.UP*bottom,b+Vector3.UP*top,mat)
		_tri(a+Vector3.UP*bottom,b+Vector3.UP*top,a+Vector3.UP*top,mat)

func _build_shell() -> void:
	_polygon_slab(-0.09,0,3)
	for wall in wall_count():
		var length := wall_length(wall)
		_wall_box(wall,0,wall_height*0.5,length+0.1,wall_height,WALL_THICKNESS,-WALL_THICKNESS*0.5,0)
		for y in [0.14,wall_height-0.08]:
			_wall_box(wall,0,y,length+0.12,0.16,0.30,-0.12,2)
		for sign_value in [-1.0,1.0]:
			if wall_finish==0: _wall_box(wall,sign_value*length*0.5,wall_height*0.5,0.13,wall_height,0.14,0.04,1)

func _build_roof_slab() -> void: _polygon_slab(wall_height,wall_height+0.18,2)
func _build_roof() -> ArrayMesh:
	if tower_roof!=0: return preload("res://addons/house_builder/conical_roof.gd").new().generate(footprint_vertices(),wall_height,maxf(roof_height,0.3),house_seed,tower_roof==2)
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
	for e in plan.levels().back().get_children():
		if e.has_method("opening_planes") and e.kind==2 and e.roof_exit and e.guardrails_enabled:
			preload("res://addons/house_builder/stair_guard.gd").append(result,e,effective_elevation(),plan.wood_material())
	return result
func stair_edge_length() -> float:
	return wall_length(stair_wall())

func hit_wall(world_origin: Vector3,world_direction: Vector3) -> Dictionary:
	var origin := to_local(world_origin); var direction := global_basis.inverse()*world_direction
	var result := {}; var closest := INF
	for wall in wall_count():
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
	if tower_roof!=0 and not conical_access_error().is_empty(): return PackedStringArray([conical_access_error()])
	if attached or wing_enabled or canopy_roof!=2 or structure_kind!=0:
		return PackedStringArray(["Torre poligonale: usare corpo indipendente chiuso, tetto piano e nessuna ala. Le altre configurazioni non sono ancora supportate."])
	return super._get_configuration_warnings()

func contains_footprint(point: Vector3,margin: float=0.0) -> bool:
	for wall in wall_count():
		if wall_normal(wall).dot(point-wall_point(wall,0,0))>=-margin: return false
	return true

func stair_wall() -> int:
	var stairs := stair_component()
	return [0,wall_count()/4,wall_count()*3/4][stairs.side] if stairs else 0

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
	for wall in wall_count():
		var normal := wall_normal(wall)
		if normal.dot(Vector3(1,0,1))>0.1:
			cuts.append([Plane(-normal,-normal.dot(wall_point(wall,0,0))+0.4),Plane(Vector3.DOWN,-floor_base-0.8)])
	return cuts


func connection_spans(wall: int,spans: Array[Vector2]) -> Array[Vector2]:
	var curtains: Array=get_children()
	if get_parent() and get_parent().has_method("curtains"): curtains=get_parent().curtains()
	for child in curtains:
		if not child.has_method("fortification_host") or not child.connect_to_tower or not child.connection_error().is_empty(): continue
		if not ((child.fortification_host()==self and child.tower_face==wall) or (child.destination()==self and child.target_face==wall)): continue
		var half: float=child.depth*0.5-0.22
		var remaining: Array[Vector2]=[]
		for span in spans:
			if span.x < -half: remaining.append(Vector2(span.x,minf(span.y,-half)))
			if span.y > half: remaining.append(Vector2(maxf(span.x,half),span.y))
		spans=remaining
	return spans
