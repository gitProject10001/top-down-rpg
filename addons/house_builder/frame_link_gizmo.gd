@tool
extends EditorNode3DGizmoPlugin
const Link=preload("res://addons/house_builder/frame_link.gd")
var focus: Node3D
func _init() -> void: create_material("outline",Color(0.2,0.85,1))
func _has_gizmo(node: Node3D) -> bool: return node is Link
func _get_gizmo_name() -> String: return "Trave e controventi"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear(); var node=gizmo.get_node_3d(); var lines := PackedVector3Array()
	for segment in node.segments():
		lines.append(node.transform.affine_inverse()*segment[0]); lines.append(node.transform.affine_inverse()*segment[1])
	gizmo.add_collision_segments(lines)
	if node==focus: gizmo.add_lines(lines,get_material("outline",gizmo))
