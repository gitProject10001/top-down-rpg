@tool
extends EditorNode3DGizmoPlugin
const Balcony=preload("res://addons/house_builder/balcony.gd")
var undo: EditorUndoRedoManager
var focus: Node3D
func _init() -> void:
	create_handle_material("handles")
	create_material("outline",Color(0.2,0.85,1))
	create_material("error",Color(1,0.15,0.1))
func _has_gizmo(node: Node3D) -> bool: return node is Balcony
func _get_gizmo_name() -> String: return "Balcone agganciato"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var n=gizmo.get_node_3d()
	var corners := PackedVector3Array([Vector3(-n.balcony_width/2,0,0),Vector3(n.balcony_width/2,0,0),Vector3(n.balcony_width/2,0,n.projection),Vector3(-n.balcony_width/2,0,n.projection)])
	var lines := PackedVector3Array()
	for i in 4: lines.append(corners[i]); lines.append(corners[(i+1)%4])
	gizmo.add_collision_segments(lines)
	if n!=focus: return
	gizmo.add_lines(lines,get_material("outline" if n.validation_error().is_empty() else "error",gizmo))
	gizmo.add_handles(PackedVector3Array([Vector3(0,0,0.2),Vector3(n.balcony_width/2,0,n.projection/2),Vector3(0,0,n.projection)]),get_material("handles",gizmo),PackedInt32Array([0,1,2]))
func _get_handle_name(_gizmo: EditorNode3DGizmo,id: int,_secondary: bool) -> String:
	return ["Posizione sulla facciata","Larghezza balcone","Profondità balcone"][id]
func _get_handle_value(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool) -> Variant:
	var n=gizmo.get_node_3d()
	return Vector4(n.along,n.elevation,n.balcony_width,n.projection)
func _set_handle(gizmo: EditorNode3DGizmo,id: int,_secondary: bool,camera: Camera3D,screen_pos: Vector2) -> void:
	var n=gizmo.get_node_3d(); var h=n.house()
	var origin := camera.project_ray_origin(screen_pos); var direction := camera.project_ray_normal(screen_pos)
	if id==0:
		if not n.door_id.is_empty(): return
		var normal: Vector3=h.global_basis*h.wall_normal(n.wall())
		var point=Plane(normal.normalized(),n.global_position).intersects_ray(origin,direction)
		if point!=null:
			var delta: Vector3=n.to_local(point)
			n.along=clampf(n.along+delta.x/(h.wall_length(n.wall())*0.5),-1,1)
			if n.floor_id.is_empty(): n.elevation=maxf(0,snappedf(n.elevation+delta.y,0.1))
	else:
		var axis: Vector3=n.global_basis.x if id==1 else n.global_basis.z
		var pair := Geometry3D.get_closest_points_between_segments(n.global_position-axis*100,n.global_position+axis*100,origin,origin+direction*1000)
		var amount: float=(pair[0]-n.global_position).dot(axis.normalized())/axis.length()
		if id==1: n.balcony_width=clampf(snappedf(amount*2,0.1),1.6,8)
		else: n.projection=clampf(snappedf(amount,0.1),0.8,4)
	h.rebuild()
func _commit_handle(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool,restore: Variant,cancel: bool) -> void:
	var n=gizmo.get_node_3d()
	if cancel: _restore(n,restore); return
	var after: Vector4=_get_handle_value(gizmo,0,false)
	undo.create_action("Modifica balcone",UndoRedo.MERGE_DISABLE,n)
	undo.add_do_method(self,"_restore",n,after); undo.add_undo_method(self,"_restore",n,restore); undo.commit_action()
func _restore(n: Node3D,value: Vector4) -> void:
	n.along=value.x; n.elevation=value.y; n.balcony_width=value.z; n.projection=value.w
	n.house().rebuild()
