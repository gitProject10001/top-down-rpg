@tool
extends EditorNode3DGizmoPlugin
const House=preload("res://addons/house_builder/house.gd")
var undo: EditorUndoRedoManager
var redraw_count := 0
var focus: Node3D
var context := 0 # 0 exterior, 1 openings, 2 hidden
var active_opening := 0
func _init() -> void:
	create_handle_material("handles")
	create_material("outline",Color(1.0,0.67,0.18))
func _has_gizmo(node: Node3D) -> bool: return node is House
func _get_gizmo_name() -> String: return "Hearth House"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	redraw_count+=1
	gizmo.clear()
	var n=gizmo.get_node_3d()
	var w: float=n.width*0.5
	var d: float=n.depth*0.5
	var h: float=n.wall_height
	var points := PackedVector3Array([Vector3(w,h*0.5,0),Vector3(-w,h*0.5,0),Vector3(0,h*0.5,d),Vector3(0,h*0.5,-d),Vector3(0,h,0),Vector3(0,h+n.roof_height,0)])
	if n.has_method("support_height") and n.structure_kind==1 and n.canopy_roof==1:
		points[4].z=d; points[5].z=-d
	if n.has_method("roof_top") and n.canopy_roof==2: points[5].y=n.roof_top()
	var ids := PackedInt32Array([0,1,2,3,4,5])
	if n.wing_enabled:
		var frame: Transform3D=n.wing_transform()
		points.append(frame*Vector3(0,h*0.5,(n.width*0.5+n.wing_length)*0.5))
		points.append(frame*Vector3(n.wing_span()*0.5,h*0.5,(n.width*0.5+n.wing_length)*0.3))
		ids.append(6); ids.append(7)
	for i in n.openings.size():
		if int(n.openings[i].get("wall",0))>=n.wall_count(): continue
		points.append(n.opening_position(i))
		ids.append(100+i)
		var o: Dictionary=n.resolved_opening(n.openings[i])
		points.append(n.wall_point(o.wall,o.along+o.width*0.5,o.y,0.12))
		points.append(n.wall_point(o.wall,o.along,o.y+o.height*0.5,0.12))
		ids.append(10000+i*2); ids.append(10001+i*2)
	var shown_points := PackedVector3Array(); var shown_ids := PackedInt32Array()
	if n==focus:
		for i in ids.size():
			if (context==0 and ids[i]<100) or (context==1 and ids[i] in [100+active_opening,10000+active_opening*2,10001+active_opening*2]):
				shown_points.append(points[i]); shown_ids.append(ids[i])
	if not shown_points.is_empty(): gizmo.add_handles(shown_points,get_material("handles",gizmo),shown_ids)
	var lines := PackedVector3Array()
	var corners := [Vector3(-w,0,-d),Vector3(w,0,-d),Vector3(w,0,d),Vector3(-w,0,d)]
	if n.has_method("footprint_vertices"): corners=n.footprint_vertices()
	for i in corners.size():
		lines.append(corners[i]); lines.append(corners[(i+1)%corners.size()])
		lines.append(corners[i]); lines.append(corners[i]+Vector3.UP*h)
	if n.wing_enabled:
		var frame: Transform3D=n.wing_transform()
		var span: float=n.wing_span()*0.5
		var length: float=(n.width*0.5+n.wing_length)*0.5
		var wing_corners := [Vector3(-span,0,-length),Vector3(span,0,-length),Vector3(span,0,length),Vector3(-span,0,length)]
		for i in 4:
			lines.append(frame*wing_corners[i]); lines.append(frame*wing_corners[(i+1)%4])
			lines.append(frame*wing_corners[i]); lines.append(frame*(wing_corners[i]+Vector3.UP*h))
	if n==focus and context<2: gizmo.add_lines(lines,get_material("outline",gizmo))
	if is_instance_valid(n._generated):
		for child in n._generated.get_children():
			if child is MeshInstance3D: gizmo.add_collision_triangles(child.mesh.generate_triangle_mesh())
func _get_handle_name(_gizmo: EditorNode3DGizmo,id: int,_secondary: bool) -> String:
	var node=_gizmo.get_node_3d()
	if id==5 and node.has_method("roof_top") and node.canopy_roof==2: return "Altezza parapetto"
	if id>=10000: return "Larghezza apertura" if id%2==0 else "Altezza apertura"
	return "Sposta apertura" if id>=100 else ["Larghezza +","Larghezza −","Lunghezza +","Lunghezza −","Altezza pareti","Altezza tetto","Lunghezza ala","Larghezza ala"][id]
func _get_handle_value(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool) -> Variant:
	var n=gizmo.get_node_3d()
	return {"dimensions":n.dimensions(),"openings":n.openings.duplicate(true),"wing":n.wing_settings()}
func _set_handle(gizmo: EditorNode3DGizmo,id: int,_secondary: bool,camera: Camera3D,screen_pos: Vector2) -> void:
	var n=gizmo.get_node_3d()
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if id>=10000:
		var index := (id-10000)/2
		var o: Dictionary=n.resolved_opening(n.openings[index])
		var vertical := id%2==1
		var tangent: Vector3=(n.wall_point(o.wall,1,0)-n.wall_point(o.wall,0,0)).normalized()
		var axis: Vector3=n.global_basis*(Vector3.UP if vertical else tangent)
		var base_y: float=o.y-o.height*0.5 if vertical and o.door else o.y
		var start: Vector3=n.to_global(n.wall_point(o.wall,o.along,base_y,0.12))
		var pair := Geometry3D.get_closest_points_between_segments(start-axis*100.0,start+axis*100.0,origin,origin+direction*1000.0)
		var amount: float=(pair[0]-start).dot(axis.normalized())/axis.length()
		var records: Array[Dictionary]=n.openings.duplicate(true)
		var maximum: float=n.wall_height-(o.y-o.height*0.5 if o.door else 0.0)-0.25 if vertical else n.wall_length(o.wall)-2.0*absf(o.along)-0.4
		if vertical and not o.door: maximum=2.0*minf(o.y-0.25,n.wall_height-0.12-o.y)
		records[index]["height" if vertical else "width"]=clampf(snappedf(amount*(1.0 if vertical and o.door else 2.0),0.05),0.35,maximum)
		records[index]["u"]=o.along/(n.wall_length(o.wall)*0.5)
		records[index]["y"]=o.y
		if n.opening_fits(records[index],index): n.openings=records
		return
	if id in [6,7]:
		var frame: Transform3D=n.wing_transform()
		var axis: Vector3=n.global_basis*(frame.basis.z if id==6 else frame.basis.x)
		var anchor: Vector3=frame*Vector3(0,n.wall_height*0.5,0 if id==6 else (n.width*0.5+n.wing_length)*0.3)
		var start: Vector3=n.to_global(anchor)
		var pair := Geometry3D.get_closest_points_between_segments(start-axis*100.0,start+axis*100.0,origin,origin+direction*1000.0)
		var amount: float=(pair[0]-start).dot(axis.normalized())/axis.length()
		if id==6: n.wing_length=snappedf(amount+(n.width*0.5+n.wing_length)*0.5-n.width*0.5,0.1)
		else: n.wing_width=snappedf(absf(amount)*2.0,0.1)
		return
	if id>=100:
		var hit: Dictionary=n.hit_wall(origin,direction)
		if hit.is_empty(): return
		var records: Array[Dictionary]=n.openings.duplicate(true)
		records[id-100].merge({"wall":hit.wall,"u":hit.u,"y":snappedf(hit.y,0.1)},true)
		if n.opening_fits(records[id-100],id-100): n.openings=records
		return
	var axis: Vector3=n.global_basis.x if id<2 else (n.global_basis.z if id<4 else n.global_basis.y)
	var start: Vector3=n.to_global(Vector3(0,n.wall_height*0.5,0)) if id<4 else n.global_position
	if id>=4 and n.has_method("support_height") and n.structure_kind==1 and n.canopy_roof==1: start=n.to_global(Vector3(0,0,n.depth*0.5 if id==4 else -n.depth*0.5))
	var pair := Geometry3D.get_closest_points_between_segments(start-axis*100.0,start+axis*100.0,origin,origin+direction*1000.0)
	var amount: float=(pair[0]-start).dot(axis.normalized())/axis.length()
	var value: Vector4=n.dimensions()
	if id<2: value.x=snappedf(absf(amount)*2.0,0.1)
	elif id<4: value.y=snappedf(absf(amount)*2.0,0.1)
	elif id==4: value.z=snappedf(amount,0.1)
	else: value.w=snappedf(amount-n.wall_height-(0.18 if n.has_method("roof_top") and n.canopy_roof==2 else 0.0),0.1)
	n.set_dimensions(value)
func _commit_handle(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool,restore: Variant,cancel: bool) -> void:
	var n=gizmo.get_node_3d()
	if cancel:
		n.set_dimensions(restore.dimensions); n.openings=restore.openings
		n.set_wing_settings(restore.wing)
		return
	undo.create_action("Modifica casa",UndoRedo.MERGE_DISABLE,n)
	undo.add_do_method(n,"set_dimensions",n.dimensions())
	undo.add_do_property(n,"openings",n.openings.duplicate(true))
	undo.add_do_method(n,"set_wing_settings",n.wing_settings())
	undo.add_undo_method(n,"set_dimensions",restore.dimensions)
	undo.add_undo_property(n,"openings",restore.openings)
	undo.add_undo_method(n,"set_wing_settings",restore.wing)
	undo.commit_action(false)
