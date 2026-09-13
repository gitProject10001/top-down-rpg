@tool
extends EditorNode3DGizmoPlugin
const Stair=preload("res://addons/house_builder/exterior_stair.gd")
var focus: Node3D
var undo: EditorUndoRedoManager
func _init() -> void:
	create_handle_material("handles"); create_material("outline",Color(0.2,0.85,1))
func _has_gizmo(node: Node3D) -> bool: return node is Stair
func _get_gizmo_name() -> String: return "Scala esterna"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear(); var node=gizmo.get_node_3d(); var host=node.terrace()
	if host==null or node!=focus: return
	var lines := PackedVector3Array()
	for x in [-node.width/2,node.width/2]:
		lines.append(Vector3(x,0,0)); lines.append(Vector3(x,node.ground_level-host.effective_elevation(),host.stair_run()))
	gizmo.add_lines(lines,get_material("outline",gizmo)); gizmo.add_collision_segments(lines)
	gizmo.add_handles(PackedVector3Array([Vector3(node.width/2,0,0.2),Vector3(0,0,0)]),get_material("handles",gizmo),PackedInt32Array([0,1]))
func _get_handle_name(_gizmo: EditorNode3DGizmo,id: int,_secondary: bool) -> String:
	return "Larghezza scala" if id==0 else "Posizione lungo il bordo"
func _get_handle_value(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool) -> Variant:
	var node=gizmo.get_node_3d(); return Vector2(node.width,node.offset)
func _set_handle(gizmo: EditorNode3DGizmo,id: int,_secondary: bool,camera: Camera3D,screen_pos: Vector2) -> void:
	var node=gizmo.get_node_3d(); var host=node.terrace()
	var axis: Vector3=node.global_basis.x; var origin := camera.project_ray_origin(screen_pos); var direction := camera.project_ray_normal(screen_pos)
	var pair := Geometry3D.get_closest_points_between_segments(node.global_position-axis*100,node.global_position+axis*100,origin,origin+direction*1000)
	var amount: float=(pair[0]-node.global_position).dot(axis.normalized())/axis.length()
	if id==0: node.width=clampf(snappedf(amount*2,0.1),0.9,2.4)
	else: node.offset=clampf(node.offset+amount/maxf(0.01,(host.stair_edge_length()-node.width)*0.5-0.2),-1,1)
	host.house().rebuild(); node.update_gizmos()
func _commit_handle(gizmo: EditorNode3DGizmo,_id: int,_secondary: bool,restore: Variant,cancel: bool) -> void:
	var node=gizmo.get_node_3d()
	if cancel: apply(node,restore); return
	undo.create_action("Modifica scala indipendente",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_method(self,"apply",node,Vector2(node.width,node.offset)); undo.add_undo_method(self,"apply",node,restore); undo.commit_action()
func apply(node: Node3D,value: Vector2) -> void:
	node.width=value.x; node.offset=value.y; node.terrace().house().rebuild(); node.update_gizmos()
