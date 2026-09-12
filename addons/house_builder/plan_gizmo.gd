@tool
extends EditorNode3DGizmoPlugin
const Element=preload("res://addons/house_builder/plan_element.gd")
var undo: EditorUndoRedoManager
func _init() -> void:
	create_handle_material("handles"); create_material("outline",Color(0.35,0.8,1.0))
func _has_gizmo(node: Node3D) -> bool: return node is Element
func _get_gizmo_name() -> String: return "House Plan Element"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var n=gizmo.get_node_3d(); var size: Vector3=n.dimensions
	var y := 0.08 if n.kind==0 else size.y*0.5
	var corners := [Vector3(-size.x*0.5,y,-size.z*0.5),Vector3(size.x*0.5,y,-size.z*0.5),Vector3(size.x*0.5,y,size.z*0.5),Vector3(-size.x*0.5,y,size.z*0.5)]
	var lines := PackedVector3Array()
	for i in 4: lines.append(corners[i]); lines.append(corners[(i+1)%4])
	gizmo.add_lines(lines,get_material("outline",gizmo))
	gizmo.add_collision_segments(lines)
	gizmo.add_handles(PackedVector3Array([Vector3(size.x*0.5,y,0),Vector3(0,y,size.z*0.5)]),get_material("handles",gizmo),PackedInt32Array([0,1]))
	if is_instance_valid(n._visual):
		for child in n._visual.get_children():
			if child is MeshInstance3D: gizmo.add_collision_triangles(child.mesh.generate_triangle_mesh())
func _get_handle_name(_g: EditorNode3DGizmo,id: int,_s: bool) -> String: return "Larghezza / lunghezza" if id==0 else "Profondità / spessore"
func _get_handle_value(g: EditorNode3DGizmo,_id: int,_s: bool) -> Variant: return g.get_node_3d().dimensions
func _set_handle(g: EditorNode3DGizmo,id: int,_s: bool,camera: Camera3D,screen: Vector2) -> void:
	var n=g.get_node_3d(); var size: Vector3=n.dimensions
	var axis: Vector3=n.global_basis.x if id==0 else n.global_basis.z
	var start: Vector3=n.to_global(Vector3(0,0.08 if n.kind==0 else size.y*0.5,0))
	var ray := camera.project_ray_origin(screen)
	var pair := Geometry3D.get_closest_points_between_segments(start-axis*100,start+axis*100,ray,ray+camera.project_ray_normal(screen)*1000)
	var amount := snappedf(absf((pair[0]-start).dot(axis.normalized())/axis.length())*2,0.05)
	if id==0: size.x=maxf(0.2,amount)
	else: size.z=maxf(0.12,amount)
	n.dimensions=size
func _commit_handle(g: EditorNode3DGizmo,_id: int,_s: bool,before: Variant,cancel: bool) -> void:
	var n=g.get_node_3d()
	if cancel: n.dimensions=before; return
	undo.create_action("Dimensioni elemento interno",UndoRedo.MERGE_DISABLE,n)
	undo.add_do_property(n,"dimensions",n.dimensions); undo.add_undo_property(n,"dimensions",before); undo.commit_action(false)
