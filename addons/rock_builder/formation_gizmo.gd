@tool
extends EditorNode3DGizmoPlugin
const Formation=preload("res://addons/rock_builder/formation.gd")
func _init() -> void:
 create_material("free",Color(0.3,1.0,0.65))
func _has_gizmo(node: Node3D) -> bool: return node is Formation
func _get_gizmo_name() -> String: return "Rock free side"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
 gizmo.clear()
 var node=gizmo.get_node_3d()
 if not EditorInterface.get_selection().get_selected_nodes().has(node): return
 if node.curve==null: return
 var lines := PackedVector3Array()
 for ribbon in node.free_ribbons():
  for i in ribbon.size():
   for p in [ribbon[i],ribbon[(i+1)%ribbon.size()]]:
    lines.append(Vector3(p.x,0.08,p.y))
 gizmo.add_lines(lines,get_material("free",gizmo))
