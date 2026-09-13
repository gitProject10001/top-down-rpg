@tool
extends EditorNode3DGizmoPlugin
const Support=preload("res://addons/house_builder/support.gd")
var focus: Node3D
func _init() -> void: create_material("outline",Color(0.2,0.85,1))
func _has_gizmo(node: Node3D) -> bool: return node is Support
func _get_gizmo_name() -> String: return "Sostegno portico"
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear(); var node=gizmo.get_node_3d()
	if not node.valid(): return
	var size: float=node.section*0.5; var h: float=node.height()
	var lines := PackedVector3Array()
	var corners := [Vector3(-size,0,-size),Vector3(size,0,-size),Vector3(size,0,size),Vector3(-size,0,size)]
	for i in 4:
		lines.append(corners[i]); lines.append(corners[i]+Vector3.UP*h)
		for y in [0.0,h]:
			lines.append(corners[i]+Vector3.UP*y); lines.append(corners[(i+1)%4]+Vector3.UP*y)
	# Picking stays available without displaying every support outline.
	gizmo.add_collision_segments(lines)
	if node==focus: gizmo.add_lines(lines,get_material("outline",gizmo))
