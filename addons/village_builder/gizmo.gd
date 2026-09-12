@tool
extends EditorNode3DGizmoPlugin
const Guide=preload("res://addons/village_builder/guide.gd")
var undo: EditorUndoRedoManager
var focus: Node3D
func _init() -> void:
	create_handle_material("handles")
	create_material("boundary",Color(0.4,0.85,0.5)); create_material("road",Color(1,0.75,0.3)); create_material("zone",Color(0.4,0.7,1))
func _has_gizmo(node: Node3D) -> bool: return node is Guide
func _get_gizmo_name() -> String: return "Village guides"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node=gizmo.get_node_3d(); var lines := PackedVector3Array(); var handles := PackedVector3Array(); var ids := PackedInt32Array()
	for i in node.points.size():
		var p: Vector2=node.points[i]; handles.append(Vector3(p.x,0.1,p.y)); ids.append(i)
		if i>0: lines.append(handles[i-1]); lines.append(handles[i])
	if node.kind!=1 and handles.size()>2: lines.append(handles[-1]); lines.append(handles[0])
	gizmo.add_lines(lines,get_material(["boundary","road","zone"][node.kind],gizmo)); gizmo.add_collision_segments(lines)
	if node==focus: gizmo.add_handles(handles,get_material("handles",gizmo),ids)
func _get_handle_name(_g: EditorNode3DGizmo,id: int,_s: bool) -> String: return "Punto %d"%(id+1)
func _get_handle_value(g: EditorNode3DGizmo,_id: int,_s: bool) -> Variant: return g.get_node_3d().points.duplicate()
func _set_handle(g: EditorNode3DGizmo,id: int,_s: bool,camera: Camera3D,screen: Vector2) -> void:
	var node=g.get_node_3d(); var inverse: Transform3D=node.global_transform.affine_inverse()
	var point=Plane(Vector3.UP,0).intersects_ray(inverse*camera.project_ray_origin(screen),inverse.basis*camera.project_ray_normal(screen))
	if point==null: return
	var points: PackedVector2Array=node.points.duplicate(); points[id]=Vector2(snappedf(point.x,0.5),snappedf(point.z,0.5)); node.points=points
func _commit_handle(g: EditorNode3DGizmo,_id: int,_s: bool,before: Variant,cancel: bool) -> void:
	var node=g.get_node_3d()
	if cancel: node.points=before; return
	undo.create_action("Sposta punto villaggio",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,"points",node.points); undo.add_undo_property(node,"points",before); undo.commit_action(false)
