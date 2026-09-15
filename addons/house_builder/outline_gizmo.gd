@tool
extends EditorNode3DGizmoPlugin
var undo: EditorUndoRedoManager
func _init() -> void:
 create_handle_material("points"); create_material("outline",Color(0.3,1,0.7))
func _has_gizmo(node: Node3D) -> bool: return node.has_method("regular_outline")
func _get_gizmo_name() -> String: return "Tower outline"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
 gizmo.clear()
 var node=gizmo.get_node_3d()
 if not gizmo.is_selected() or not node.edit_outline: return
 var points := PackedVector3Array(node.footprint_vertices())
 var lines := PackedVector3Array(); var ids := PackedInt32Array()
 for i in points.size():
  points[i].y=0.08; ids.append(i)
 for i in points.size(): lines.append(points[i]); lines.append(points[(i+1)%points.size()])
 gizmo.add_lines(lines,get_material("outline",gizmo)); gizmo.add_handles(points,get_material("points",gizmo),ids)
func _get_handle_name(_g: EditorNode3DGizmo,id: int,_s: bool) -> String: return "Vertice %d"%id
func _get_handle_value(g: EditorNode3DGizmo,_id: int,_s: bool) -> Variant: return g.get_node_3d().custom_outline.duplicate()
func _set_handle(g: EditorNode3DGizmo,id: int,_s: bool,camera: Camera3D,screen: Vector2) -> void:
 var node=g.get_node_3d(); var inverse: Transform3D=node.global_transform.affine_inverse()
 var hit=Plane(Vector3.UP,0).intersects_ray(inverse*camera.project_ray_origin(screen),inverse.basis*camera.project_ray_normal(screen))
 if hit==null: return
 var points: PackedVector2Array=node.custom_outline.duplicate() if not node.custom_outline.is_empty() else node.regular_outline()
 points[id]=Vector2(snappedf(hit.x,0.1)/node.width,snappedf(hit.z,0.1)/node.depth)
 if node.outline_error(points).is_empty(): node.custom_outline=points
func _commit_handle(g: EditorNode3DGizmo,_id: int,_s: bool,before: Variant,cancel: bool) -> void:
 var node=g.get_node_3d()
 if cancel: node.custom_outline=before; return
 undo.create_action("Modifica sagoma torre",UndoRedo.MERGE_DISABLE,node)
 undo.add_do_property(node,"custom_outline",node.custom_outline.duplicate()); undo.add_undo_property(node,"custom_outline",before); undo.commit_action(false)
